-- server/test/test_ghost_sync.lua
-- Real -> Ghost 同步链路测试。
-- real 属性变更 -> collectGhostDirty -> broadcastGhost -> ghost.stageProp -> collectStage。

package.path = "./?.lua;./?/init.lua;" .. package.path

local spaceLib = require "tinyworld.space.space"
local localSpaceMod = require "tinyworld.app.cellapp.local_space"
local entities = require "tinyworld.app.cellapp.entities"
local defs = require "tinyworld.entity.defs"

defs.register("GhostDummy", {
    name = "GhostDummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
        { name = "level", type = "number", sync = "all" },
        { name = "secret", type = "number", sync = "self" },
    },
})

local config = spaceLib.SpaceConfig.compile({ id = "ghost", width = 200, height = 200,
    cellSize = 100, aoiRange = 40 }, { 1 })

local fake = {
    appId = 1,
    spaceConfig = config,
    call = function(self, ...) return true end,
    send = function(self, ...) end,
    sendToClient = function(self, ...) end,
    notifyEntityMoved = function(self, ...) end,
    nextId = function(self) self.seq = (self.seq or 0) + 1 return 5000 + self.seq end,
}

local space = localSpaceMod.LocalSpace.new(fake)
for _, info in ipairs(config.cells) do
    space:addLocalCell(info)
end

local cellA = space:getCell("0:0")
local cellB = space:getCell("1:0")

-- real 放 cellA, 同时在 cellB 造一个 ghost(模拟跨 cell 可见)
local real = entities.RealEntity.new(defs.get("GhostDummy"), 1001, "GhostDummy", space, cellA, 10, 10)
cellA:addEntity(real)

local ghost = space:buildGhost(real, cellB, 10, 10)
cellB:addEntity(ghost)
real:addGhost({ key = "1001@1:0", app = 1, cellKey = "1:0", sameApp = true })

-- real 属性变更会产生 ghost dirty
real:set("x", 30)
local dirty = real:collectGhostDirty()
assert(dirty and dirty.x == 30, "ghost dirty not collected")

-- broadcastGhost 把 stage 写进 ghost 的 next-tick 队列
space:broadcastGhost(real, dirty)
local stage = ghost:collectStage()
assert(stage.x == 30, "ghost stage not set")

-- ghost 下一个 tick 应把 stage 发给观察者(此处只验证 stage 被取走)
assert(next(ghost:collectStage()) == nil)

print("PASS test_ghost_sync")
