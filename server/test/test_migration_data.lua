-- server/test/test_migration_data.lua
-- 迁移后对象数据一致性测试: 属性 / 表格 / 容器自身 props / 容器子对象。
-- 覆盖本地迁移(同 cellapp)与跨 app 迁移(远端 ghost_promote)。

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LocalSpace = require "tinyworld.app.cellapp.space.local_space"
local RealEntity = require "tinyworld.app.cellapp.entities.real_entity"

defs.register("MigrateDataDummy", {
    name = "MigrateDataDummy",
    props = {
        { name = "x", type = "number", sync = "all", default = 0 },
        { name = "y", type = "number", sync = "all", default = 0 },
        { name = "hp", type = "number", sync = "all", default = 100 },
    },
    records = {
        { name = "tasks", keyFields = { "taskid" }, sync = "all", persist = true, fields = {
            { name = "taskid", type = "number", sync = "all" },
            { name = "progress", type = "number", sync = "all", default = 0 },
        } },
    },
    containers = {
        { name = "bag", persist = true, sync = "all",
          props = { { name = "capacity", type = "number", sync = "all", default = 32 } },
          childDef = { name = "item",
              props = {
                  { name = "id", type = "number", sync = "all" },
                  { name = "itemId", type = "number", sync = "all" },
                  { name = "count", type = "number", sync = "all", default = 1 },
              },
              records = {
                  { name = "enchants", keyFields = { "slot" }, sync = "all", persist = true, fields = {
                      { name = "slot", type = "number", sync = "all" },
                      { name = "value", type = "number", sync = "all" },
                  } },
              } } },
    },
})

local function buildCluster(spaceId, config, appIds)
    local apps, spaces, rebinds, promotes = {}, {}, {}, {}
    for _, appId in ipairs(appIds) do
        local app = { appId = appId, seq = 0, time = 100, spaceConfig = config }
        function app:now() return self.time end
        function app:nextId() self.seq = self.seq + 1 return appId * 10000 + self.seq end
        function app:sendToClient() end
        function app:notifyEntityMoved(real) end

        function app:call(targetAppId, command, ...)
            local peer = spaces[targetAppId]
            if not peer then return false end
            local s2, cellKey, req = ...
            local cell = peer:getCell(cellKey)
            if not cell then return false end
            if command == "ghost_create" then return cell:upsertRemoteGhost(req) end
            return true
        end

        function app:send(targetAppId, command, ...)
            local peer = spaces[targetAppId]
            if not peer then return end
            local s2, cellKey, realId, req = ...
            local cell = peer and peer:getCell(cellKey)
            if not cell then return end
            if command == "ghost_promote" then
                promotes[#promotes + 1] = { cellKey = cellKey }
                local real = cell:promoteGhost(realId, req)
                if not real then return end
                if real.baseApp then rebinds[#rebinds + 1] = { playerId = real.playerId, cellKey = cellKey } end
            end
        end

        apps[appId] = app
        local space = LocalSpace.new(app)
        for _, info in ipairs(config.cells) do
            if info.appId == appId then space:addLocalCell(info) end
        end
        spaces[appId] = space
    end
    return apps, spaces, rebinds, promotes
end

local function tickAll(spaces, dt)
    for _, space in pairs(spaces) do space:tick(dt) end
end

local function assertData(real, empty)
    assert(real:get("hp") == 500, "hp lost")
    local rec = real:getRecord("tasks")
    local row = rec:get("101")
    if empty == false then
        assert(row and row.taskid == 101 and row.progress == 3, "record row lost")
    end
    local bag = real:getContainer("bag")
    assert(bag.capacity == 32, "container prop lost")
    if empty == false then
        local child = bag:get(1)
        assert(child and child.itemId == 7001 and child.count == 3, "child data lost")
        local childRec = child.records and child.records.enchants
        local ench = childRec and childRec:get("1")
        assert(ench and ench.value == 10, "child record lost")
    end
end

-- 本地迁移(单 cellapp, 0:0 -> 1:0)
do
    local config = SpaceConfig.compile({ id = "mdlocal", width = 200, height = 100,
        aoiRange = 30, ghostRange = 40, cellSize = 100, minMigrateInterval = 0, hysteresis = 5 })
    CellAllocator.distribute(config, { 1 })

    local app = { appId = 1, seq = 0, time = 100, spaceConfig = config }
    function app:now() return self.time end
    function app:nextId() self.seq = self.seq + 1 return 10000 + self.seq end
    function app:sendToClient() end
    function app:notifyEntityMoved() end
    local space = LocalSpace.new(app)
    for _, info in ipairs(config.cells) do space:addLocalCell(info) end
    local cellA = space:getCell("0:0")
    local cellB = space:getCell("1:0")

    local real = RealEntity.new(defs.get("MigrateDataDummy"), 1001, "MigrateDataDummy", space, cellA)
    real.props:load({ x = 20, y = 50, hp = 500 })
    real.cellInitData = { abilities = {} }
    real:getRecord("tasks"):add({ taskid = 101, progress = 3 })
    real:getContainer("bag").capacity = 32
    real:getContainer("bag"):addFromData({ id = 1, itemId = 7001, count = 3 })
    real:getContainer("bag"):get(1).records.enchants:add({ slot = 1, value = 10 })
    cellA:addEntity(real)

    real:set("x", 150)
    tickAll({ space }, 0)

    local moved = cellB:get(1001)
    assert(moved and moved.isReal, "local migrate failed")
    assertData(moved, false)
    print("PASS migration-data-local")
end

-- 跨 app 迁移(0:0(app1) -> 1:0(app2))
do
    local config = SpaceConfig.compile({ id = "mdremote", width = 200, height = 100,
        aoiRange = 30, ghostRange = 40, cellSize = 100, minMigrateInterval = 0, hysteresis = 5 })
    CellAllocator.distribute(config, { 1, 2 })
    local apps, spaces, rebinds, promotes = buildCluster("mdremote", config, { 1, 2 })
    local cellA = spaces[1]:getCell("0:0")
    local cellB = spaces[2]:getCell("1:0")

    local real = RealEntity.new(defs.get("MigrateDataDummy"), 2001, "MigrateDataDummy", spaces[1], cellA)
    real.playerId = 2001
    real.baseApp = 999
    real.props:load({ x = 20, y = 50, hp = 500 })
    real:getRecord("tasks"):add({ taskid = 101, progress = 3 })
    real:getContainer("bag").capacity = 32
    real:getContainer("bag"):addFromData({ id = 1, itemId = 7001, count = 3 })
    real:getContainer("bag"):get(1).records.enchants:add({ slot = 1, value = 10 })
    cellA:addEntity(real)

    real:set("x", 150)
    tickAll(spaces, 0)

    assert(#promotes == 1, "remote promote not fired")
    local moved = cellB:get(2001)
    assert(moved and moved.isReal, "remote migrate failed")
    assertData(moved, false)
    assert(#rebinds == 1, "rebind not fired")
    print("PASS migration-data-remote")
end

print("ALL MIGRATION DATA TESTS PASS")
