-- server/test/test_space.lua
-- Space / Cell / AOI / 跨 cell 迁移(同 app) 的单元测试。
-- 用 fake app 替代 skynet, 单独验证 localspace 迁移与抗抖动逻辑。

package.path = "./?.lua;./?/init.lua;" .. package.path

local spaceLib = require "tinyworld.space.space"
local localSpaceMod = require "tinyworld.app.cellapp.local_space"
local entities = require "tinyworld.app.cellapp.entities"
local defs = require "tinyworld.entity.defs"

-- 定义 cell 侧实体
defs.register("Dummy", {
    name = "Dummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
        { name = "speed", type = "number", sync = "all", default = 5 },
    },
})

local config = spaceLib.SpaceConfig.compile({ id = "test", width = 200, height = 200, cellSize = 100,
    aoiRange = 30, minMigrateInterval = 0, hysteresis = 5 }, { 1 })

local fake = {
    appId = 1,
    time = 100,
    spaceConfig = config,
    now = function(self) return self.time end,
    nextId = function(self) self.seq = (self.seq or 0) + 1 return 1000 + self.seq end,
    call = function(self, ...) return true end,
    send = function(self, ...) end,
    sendToClient = function(self, ...) end,
    notifyEntityMoved = function(self, ...) end,
}

local space = localSpaceMod.LocalSpace.new(fake)
for _, info in ipairs(config.cells) do
    space:addLocalCell(info)
end

local cell = space:getCell("0:0")
assert(cell)
local real = entities.RealEntity.new(defs.get("Dummy"), fake:nextId(), "Dummy", space, cell, 95, 50)
real.props:load({ x = 95, y = 50 })
cell:addEntity(real)
assert(cell.playerCount == 0)

-- 边界抖动抑制: 略过边界不应迁移
real.x = 99
space:maintainEntityCells(real)
assert(real.cell.info.id == "0:0")

-- 深入目标 cell 后迁移到 1:0
fake.time = 110
real.x = 130
real.y = 50
space:maintainEntityCells(real)
assert(real.cell.info.id == "1:0")
assert(real.lastMigrateTime == 110)

-- 旧 cell 留下见证 ghost
local oldCell = space:getCell("0:0")
local foundGhost
for _, e in pairs(oldCell.entities) do
    if e.isGhost and e.realId == real.id then foundGhost = e end
end
assert(foundGhost, "witness ghost not created")

-- 再回移但未满足最小间隔/阈值 -> 不抖
real.x = 96
space:maintainEntityCells(real)
assert(real.cell.info.id == "1:0")

-- ghost 属性同步由 broadcastGhost 驱动
real:set("x", 140)
local dirty = real:collectGhostDirty()
assert(dirty and dirty.x == 140)
space:broadcastGhost(real, dirty)
foundGhost = nil
for _, e in pairs(oldCell.entities) do
    if e.isGhost and e.realId == real.id then foundGhost = e end
end
assert(foundGhost and foundGhost.props:get("x") == 140)

print("PASS test_space")
