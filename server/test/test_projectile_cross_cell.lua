-- server/test/test_projectile_cross_cell.lua
-- 跨 cell 投掷物阶段1测试(同 cellapp)。
-- 投掷物标记为 migratable=false, 越过 cell 边界仍留在原 cell, 不做迁移。

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
p.props:load({ x = 90, y = 50, dir = 0, speed = 200, range = 80, hitRadius = 2 })
rawset(p, "runtime", { movement = "linear" })
cellA:addEntity(p)
p:openViews(p.def.cellOpenViews)
p:setupComponents(p.def.cellComponents)
p.readyForSync = true

fake.time = 110
cellA:tick(0.1)

assert(p.cell.info.id == "0:0", "projectile should stay in origin cell")

-- 不迁移但仍持续运动
local move = p:getComponent("projectile")
assert(move and not move.destroyed, "projectile component should keep running")
local oldX = p.x
move:onTick(0.1)
assert(p.x > oldX, "projectile should keep moving without migration")

-- 阶段2: 不迁移, 但能在本 cellapp 其他 cell 找到追踪目标
local target = RealEntity.new(defs.get("Projectile"), 7002, "Projectile", space, cellB)
target.props:load({ x = 120, y = 50 })
cellB:addEntity(target)

local hitData

local tracker = RealEntity.new(defs.get("Projectile"), 7003, "Projectile", space, cellA)
tracker.props:load({ x = 10, y = 50, targetId = 7002, speed = 500, range = 200, hitRadius = 2 })
rawset(tracker, "runtime", {
    movement = "homing",
    onHit = function(_, targets)
        hitData = targets
        return "destroy"
    end,
})
cellA:addEntity(tracker)
tracker:openViews(tracker.def.cellOpenViews)
tracker:setupComponents(tracker.def.cellComponents)
tracker.readyForSync = true

local trackMove = tracker:getComponent("projectile")
while not trackMove.destroyed do trackMove:onTick(0.01) end

assert(tracker.cell.info.id == "0:0", "tracker should stay in origin cell")
assert(hitData, "tracking projectile should find target in another cell")
assert(#hitData == 1 and hitData[1] == target, "cross-cell tracking target mismatch")

print("PASS test_projectile_cross_cell")
