-- server/test/test_ghost_promote.lua
-- 跨 cellapp 迁移端到端测试(组件级):
-- real 从 app1 的 cell 迁到 app2 的 cell, 依次走:
--   ghost_create(远端建 ghost) -> ghost_promote(远端提升为 real)
--   -> real 重新装配组件 -> baseapp rebind_cell。
-- 用 fake app 模拟两个 cellapp 间 call/send 路由。

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
        { name = "speed", type = "number", sync = "all", default = 5 },
    },
    records = {},
    containers = {},
})

local config = SpaceConfig.compile({
    id = "mv",
    width = 200,
    height = 100,
    aoiRange = 30,
    ghostRange = 40,
    cellSize = 100,
    minMigrateInterval = 0,
    hysteresis = 5,
})
CellAllocator.distribute(config, { 1, 2 })

local localSpaces = {}
local rebind = {}
local promoteCalls = 0

local function newApp(appId)
    local app = {
        appId = appId,
        time = 100,
        spaceConfig = config,
        seq = 0,
        now = function(self) return self.time end,
        nextId = function(self) self.seq = self.seq + 1 return appId * 1000 + self.seq end,
        sendToClient = function() end,
        notifyEntityMoved = function() end,
    }

    function app:call(targetAppId, command, ...)
        local peer = localSpaces[targetAppId]
        if not peer then return true end

        local spaceId, cellKey, req = ...
        local cell = peer:getCell(cellKey)
        if not cell then return false end

        if command == "ghost_create" then
            return cell:upsertRemoteGhost(req)
        end
        return true
    end

    function app:send(targetAppId, command, ...)
        if command ~= "ghost_promote" then return end

        promoteCalls = promoteCalls + 1
        local spaceId, cellKey, realId, req = ...
        local peer = localSpaces[targetAppId]
        local cell = peer and peer:getCell(cellKey)
        if not cell then return end

        local real = cell:promoteGhost(realId, req)
        if not real then return end

        -- 与 cellapp.cmd.ghost_promote 一致: 迁移后重新装配组件
        real:setupComponents(real.def.cellComponents)
        real:openViews(real.def.cellOpenViews)
        real.readyForSync = true

        if real.baseApp then
            rebind[real.playerId] = { spaceId = spaceId, cellKey = cellKey, appAddr = targetAppId }
        end
    end

    local space = LocalSpace.new(app)
    for _, info in ipairs(config.cells) do
        if info.appId == appId then
            space:addLocalCell(info)
        end
    end
    localSpaces[appId] = space
    return app, space
end

local app1, space1 = newApp(1)
local app2, space2 = newApp(2)

local cellA = space1:getCell("0:0")
local cellB = space2:getCell("1:0")
assert(cellA and cellB)

local real = RealEntity.new(defs.get("MigrateDummy"), 42, "MigrateDummy", space1, cellA)
real.playerId = 7
real.props:load({ x = 20, y = 50 })
real.baseApp = 999
cellA:addEntity(real)

-- 推进时间并深入本 app 之外的 cell 1:0
app1.time = 110
real:set("x", 150)
real:set("y", 50)
cellA:tick(0)

assert(promoteCalls == 1, "ghost_promote not sent")
local oldEntity = cellA:get(real.id)
assert(oldEntity == nil or not oldEntity.isReal, "real should leave origin cell")
assert(rebind[7] and rebind[7].cellKey == "1:0", "baseapp rebind_cell not notified")

local promoted = cellB:get(real.id)
assert(promoted and promoted.isReal, "real promoted on target cellapp")
assert(promoted.playerId == 7, "playerId preserved after promote")
assert(promoted.baseApp == 999, "baseApp preserved after promote")

-- 原 cell 留下 witness ghost, 供旧 cell 内观察者继续看到对象
local witness
for _, e in pairs(cellA.entities) do
    if e.isGhost and e.realId == real.id then witness = e end
end
assert(witness, "witness ghost missing in origin cell")

print("PASS test_ghost_promote")
