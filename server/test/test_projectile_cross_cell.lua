-- server/test/test_projectile_cross_cell.lua
-- 跨 cell 投掷物迁移测试(同 cellapp)。
-- 直线投掷物越过 cell 边界后, 新 cell 拥有 real, 旧 cell 留下 witness/ghost。

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LocalSpace = require "tinyworld.app.cellapp.local_space"
local RealEntity = require "tinyworld.app.cellapp.real_entity"

defs.register("Projectile", require "game.def.projectile.projectile_def")

local config = SpaceConfig.compile({
    id = "cross",
    width = 200,
    height = 100,
    aoiRange = 30,
    ghostRange = 40,
    cellSize = 100,
    minMigrateInterval = 0,
    hysteresis = 2,
})
CellAllocator.distribute(config, { 1 })

local fake = {
    appId = 1,
    time = 100,
    spaceConfig = config,
    now = function(self) return self.time end,
    nextId = function(self) self.seq = (self.seq or 0) + 1 return 5000 + self.seq end,
    call = function(self, ...) return true end,
    send = function(self, ...) end,
    sendToClient = function(self, ...) end,
    notifyEntityMoved = function(self, ...) end,
}

local space = LocalSpace.new(fake)
for _, info in ipairs(config.cells) do
    space:addLocalCell(info)
end

local cellA = space:getCell("0:0")
local cellB = space:getCell("1:0")
assert(cellA and cellB)

local p = RealEntity.new(defs.get("Projectile"), 7001, "Projectile", space, cellA)
p.props:load({ x = 90, y = 50, dir = 0, speed = 200, range = 80, hitRadius = 2, pierce = true })
cellA:addEntity(p)
p:openViews(p.def.cellOpenViews)
p:setupComponents(p.def.cellComponents)
p.readyForSync = true

fake.time = 110
cellA:tick(0.1)

assert(p.cell.info.id == "1:0", "projectile should migrate to cell 1:0")

local witness
for _, e in pairs(cellA.entities) do
    if e.isGhost and e:getRealId() == p:getRealId() then witness = e end
end
assert(witness, "old cell should keep witness ghost")

-- 迁移后运动组件继续工作
local move = p:getComponent("projectile")
assert(move and not move.destroyed, "projectile component should survive migration")
local oldX = p.x
move:onTick(0.1)
assert(p.x > oldX, "projectile should keep moving after migration")

print("PASS test_projectile_cross_cell")
