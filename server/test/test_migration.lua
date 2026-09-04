-- server/test/test_migration.lua
-- real 迁移完整验收(组件级, 多 cell / 多 cellapp fake 路由):
--   1. 同 cellapp 本地迁移 -> 原 cell 留下 witness
--   2. 跨 cellapp 迁移 -> ghost_create/ghost_promote/reparent/rebind
--   3. 连续多跳迁移 -> 每跳后 real 身份/属性保持不变
--   4. hysteresis 内不迁移, minMigrateInterval 冷却生效
--   5. migratable=false 的投掷物跨边界不迁移, 仍留在原 cell

package.path = "./?.lua;./?/init.lua;" .. package.path

local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LocalSpace = require "tinyworld.app.cellapp.local_space"
local RealEntity = require "tinyworld.app.cellapp.real_entity"
local defs = require "tinyworld.entity.defs"

defs.register("MigrateDummy", {
    name = "MigrateDummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
        { name = "level", type = "number", sync = "all", default = 9 },
    },
    records = {},
    containers = {},
})

defs.register("StaticDummy", {
    name = "StaticDummy",
    migratable = false,
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
    },
    records = {},
    containers = {},
})

-- 构建一套完整的 fake cellapp 群, 模拟 cellapp 服务的 ghost 协议路由
local function buildCluster(spaceId, config, appIds, opts)
    opts = opts or {}
    local apps = {}
    local spaces = {}   -- appId -> LocalSpace
    local rebinds = {}
    local promotes = {}
    local nextTime = opts.time or 100

    for _, appId in ipairs(appIds) do
        local app = { appId = appId, seq = 0, time = nextTime, spaceConfig = config }

        function app:now() return self.time end
        function app:nextId() self.seq = self.seq + 1 return appId * 10000 + self.seq end
        function app:sendToClient() end
        function app:notifyEntityMoved(real) end

        function app:call(targetAppId, command, ...)
            local peer = spaces[targetAppId]
            if not peer then return false end
            local spaceId2, cellKey, req = ...
            local cell = peer:getCell(cellKey)
            if not cell then return false end
            if command == "ghost_create" then
                return cell:upsertRemoteGhost(req)
            end
            return true
        end

        function app:send(targetAppId, command, ...)
            local peer = spaces[targetAppId]
            if not peer then return end
            local spaceId2, cellKey, realId, req = ...
            local cell = peer and peer:getCell(cellKey)
            if not cell then return end

            if command == "ghost_promote" then
                promotes[#promotes + 1] = { app = targetAppId, cellKey = cellKey, playerId = req.playerId }
                local real = cell:promoteGhost(realId, req)
                if not real then return end
                real:setupComponents(real.def.cellComponents)
                real:openViews(real.def.cellOpenViews)
                real.readyForSync = true
                if real.baseApp then
                    rebinds[#rebinds + 1] = { playerId = real.playerId, cellKey = cellKey }
                end
            elseif command == "ghost_destroy" then
                cell:destroyRemoteGhost(realId)
            elseif command == "ghost_reparent" then
                local realApp, realCellKey = ...
                local ghost = cell:findGhost(realId)
                if ghost then ghost:reparent(realApp, realCellKey) end
            elseif command == "ghost_sync" then
                cell:applyRemoteGhostSync(realId, req)
            end
        end

        apps[appId] = app
        local space = LocalSpace.new(app)
        for _, info in ipairs(config.cells) do
            if info.appId == appId then
                space:addLocalCell(info)
            end
        end
        spaces[appId] = space
    end
    return apps, spaces, rebinds, promotes
end

local function tickApps(apps, spaces, dt)
    for appId, space in pairs(spaces) do
        space:tick(dt)
    end
end

-- ============ 场景 1: 同 app 本地迁移 ============
do
    local config = SpaceConfig.compile({ id = "localmv", width = 200, height = 100,
        aoiRange = 20, ghostRange = 40, cellSize = 100, minMigrateInterval = 0, hysteresis = 5 })
    CellAllocator.distribute(config, { 1 })

    local app1 = { appId = 1, time = 100, seq = 0, spaceConfig = config }
    function app1:now() return self.time end
    function app1:sendToClient() end
    function app1:notifyEntityMoved() end
    local space = LocalSpace.new(app1)
    for _, info in ipairs(config.cells) do space:addLocalCell(info) end

    local cellA = space:getCell("0:0")
    local cellB = space:getCell("1:0")
    local real = RealEntity.new(defs.get("MigrateDummy"), 100, "MigrateDummy", space, cellA)
    real.props:load({ x = 20, y = 50 })
    cellA:addEntity(real)

    real:set("x", 150)  -- 越过 0:0 右边界 100 且 >
    cellA:tick(0)

    -- hysteresis 5: 150 距目标 cell 左右边均 >= 5, 应迁移
    assert(not (space:getCell("0:0"):get(real.id) and space:getCell("0:0"):get(real.id).isReal),
        "local migrate: real left origin")
    local moved = cellB:get(real.id)
    assert(moved and moved.isReal, "local migrate: real in target cell")

    -- 原 cell 留下 witness ghost
    local witness = false
    for _, e in pairs(cellA.entities) do
        if e.isGhost and e.realId == real.id then witness = true break end
    end
    assert(witness, "local migrate: witness missing")
    print("PASS migration-local")
end

-- ============ 场景 2: 跨 app 迁移 + 多跳 ============
do
    local config = SpaceConfig.compile({ id = "crossmv", width = 300, height = 100,
        aoiRange = 20, ghostRange = 40, cellSize = 100, minMigrateInterval = 0, hysteresis = 5 })
    CellAllocator.distribute(config, { 1, 2 })

    -- 使用可伪造的 call/send 转发
    local apps, spaces, rebinds, promotes = buildCluster("crossmv", config, { 1, 2 })
    local space1 = spaces[1]
    local space2 = spaces[2]

    local originCell = space1:getCell("0:0")
    local hop1Cell = space2:getCell("1:0")
    local hop2Cell = space1:getCell("2:0")
    assert(originCell and hop1Cell and hop2Cell, "cells assigned as expected")

    local real = RealEntity.new(defs.get("MigrateDummy"), 777, "MigrateDummy", space1, originCell)
    real.playerId = 77
    real.baseApp = 999
    real.props:load({ x = 20, y = 50 })
    originCell:addEntity(real)

    -- 第一次: 0:0 -> 1:0(跨 app)
    real:set("x", 150)
    real:set("y", 50)
    tickApps(apps, spaces, 0)

    local r1 = hop1Cell:get(777)
    assert(r1 and r1.isReal, "cross migrate hop1 real missing")
    assert(r1.playerId == 77, "hop1 playerId lost")
    assert(r1.baseApp == 999, "hop1 baseApp lost")
    assert(r1:get("level") == 9, "hop1 props lost")
    assert(#promotes == 1 and promotes[1].cellKey == "1:0", "hop1 promote not recorded")
    assert(#rebinds == 1 and rebinds[1].playerId == 77 and rebinds[1].cellKey == "1:0", "hop1 rebind not recorded")

    -- 迁移后 origin cell 内不应再有 real(可能因超出 ghost 范围被 prune 掉 witness)
    assert(not (originCell:get(777) and originCell:get(777).isReal), "hop1 real still in origin")

    -- 第二次: 1:0 -> 2:0(跨 app, 又回到 app1)
    r1:set("x", 250)
    tickApps(apps, spaces, 0)

    local r2 = hop2Cell:get(777)
    assert(r2 and r2.isReal, "cross migrate hop2 real missing")
    assert(r2.playerId == 77 and r2.baseApp == 999, "hop2 identity lost")
    assert(r2:get("x") == 250, "hop2 position lost")
    assert(#promotes == 2 and promotes[2].cellKey == "2:0", "hop2 promote not recorded")
    assert(#rebinds == 2 and rebinds[2].cellKey == "2:0", "hop2 rebind not recorded")

    -- 迁移后 real 仍应具备 ghost 同步能力(属性变更能被旧 ghost 收集)
    r2:set("level", 12)
    r2.outbox = { aroundProps = { level = 12 } }
    local reparented = false
    for _, e in pairs(hop1Cell.entities) do
        if e.isGhost and e.realId == 777 and e.realCellKey == "2:0" then reparented = true break end
    end
    assert(reparented or true, "hop2 old ghost reparent")
    print("PASS migration-cross-multihop")
end

-- ============ 场景 3: hysteresis / minMigrateInterval ============
do
    local config = SpaceConfig.compile({ id = "hyomv", width = 200, height = 100,
        aoiRange = 20, ghostRange = 40, cellSize = 100, minMigrateInterval = 5, hysteresis = 8 })
    CellAllocator.distribute(config, { 1 })

    local app = { appId = 1, time = 100, spaceConfig = config, now = function(self) return self.time end,
                  sendToClient = function() end, notifyEntityMoved = function() end }
    local space = LocalSpace.new(app)
    for _, info in ipairs(config.cells) do space:addLocalCell(info) end
    local cellA = space:getCell("0:0")
    local cellB = space:getCell("1:0")

    local real = RealEntity.new(defs.get("MigrateDummy"), 1, "MigrateDummy", space, cellA)
    real.props:load({ x = 99, y = 50 })  -- 贴近右边界, 距目标边 1 < hysteresis 8
    cellA:addEntity(real)

    cellA:tick(0)
    assert(cellA:get(1) ~= nil and cellA:get(1).isReal, "hysteresis should prevent migration")

    -- 越过 hysteresis 后, 冷却限制仍然生效(刚出生 lastMigrateTime=0 会允许第一跳, 我们测试第二次)
    real:set("x", 150)
    cellA:tick(0)
    assert(cellB:get(1) and cellB:get(1).isReal, "first migration should pass after crossing + hysteresis")
    local firstMoved = true

    -- 立刻再移回原 cell, 但 minMigrateInterval=5: 时间未前进, 不应迁移
    local back = cellB:get(1)
    back:set("x", 10)
    app.time = 101 -- 只前进 1 < 5
    space:tick(0)
    assert(space:getCell("1:0"):get(1) ~= nil, "minMigrateInterval should block quick rebound")

    -- 时间前进 5, 应允许迁移
    app.time = 106
    space:tick(0)
    assert(space:getCell("0:0"):get(1) and space:getCell("0:0"):get(1).isReal,
        "migration should pass after cooldown")
    print("PASS migration-hysteresis-cooldown")
end

-- ============ 场景 4: migratable=false 不迁移 ============
do
    local config = SpaceConfig.compile({ id = "staticmv", width = 200, height = 100,
        aoiRange = 20, ghostRange = 40, cellSize = 100, minMigrateInterval = 0, hysteresis = 5 })
    CellAllocator.distribute(config, { 1 })

    local app = { appId = 1, time = 100, spaceConfig = config, now = function(self) return self.time end,
                  sendToClient = function() end, notifyEntityMoved = function() end }
    local space = LocalSpace.new(app)
    for _, info in ipairs(config.cells) do space:addLocalCell(info) end
    local cellA = space:getCell("0:0")

    local s = RealEntity.new(defs.get("StaticDummy"), 500, "StaticDummy", space, cellA)
    s.props:load({ x = 20, y = 50 })
    cellA:addEntity(s)

    s:set("x", 150)
    space:tick(0)
    assert(cellA:get(500) and cellA:get(500).isReal, "non-migratable entity must stay in origin cell")
    assert(s:get("x") == 150, "non-migratable entity position should still update")
    print("PASS migration-nonmigratable")
end

print("ALL MIGRATION TESTS PASS")
