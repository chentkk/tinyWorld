-- server/test/test_space.lua
-- Space / Cell / AOI / 跨 cell 迁移(同 app) 的单元测试。
-- 用 fake app 替代 skynet, 单独验证 localspace 迁移与抗抖动逻辑。

package.path = "./?.lua;./?/init.lua;" .. package.path

local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LocalSpace = require "tinyworld.app.cellapp.local_space"
local RealEntity = require "tinyworld.app.cellapp.real_entity"
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

local config = SpaceConfig.compile({ id = "test", width = 200, height = 200, cellSize = 100,
    aoiRange = 30, minMigrateInterval = 0, hysteresis = 5 })
CellAllocator.distribute(config, { 1 })

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

local space = LocalSpace.new(fake)
for _, info in ipairs(config.cells) do
    space:addLocalCell(info)
end

local cell = space:getCell("0:0")
assert(cell)
local real = RealEntity.new(defs.get("Dummy"), fake:nextId(), "Dummy", space, cell, 95, 50)
real.props:load({ x = 95, y = 50 })
cell:addEntity(real)
assert(cell.playerCount == 0)

-- 边界抖动抑制: 略过边界不应迁移
real.x = 99
cell:tick(0)
assert(real.cell.info.id == "0:0")

-- AOI 网格应跟随位置变化
local seenInAoi = false
for _, e in ipairs(cell:queryRange(99, 50)) do
    if e == real then seenInAoi = true break end
end
assert(seenInAoi, "aoi grid not synced after move")

-- 深入目标 cell 后迁移到 1:0
fake.time = 110
real.x = 130
real.y = 50
cell:tick(0)
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
cell:tick(0)
assert(real.cell.info.id == "1:0")

-- Real -> Ghost: cell 内广播用 real.outbox
real:set("x", 140)
real.outbox = { aroundProps = { x = 140 } }
real:sendGhostEach(real.outbox)
foundGhost = nil
for _, e in pairs(oldCell.entities) do
    if e.isGhost and e.realId == real.id then foundGhost = e end
end
assert(foundGhost and foundGhost.props:get("x") == 140)

print("PASS test_space")
