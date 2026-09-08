-- server/test/test_projectile.lua
-- 通用战斗实体(Projectile)运动与命中回调测试:
--   * homing: 追踪目标, onHit 返回 "destroy" 即销毁
--   * linear: 直线前进, 命中范围内候选, onHit 可继续前进
--   * range: 超距销毁
-- 组件不内置伤害; 行为由使用层 runtime 回调决定。

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local Entity = require "tinyworld.entity.entity"
local SpatialIndex = require "tinyworld.app.cellapp.space.spatial_index"

defs.register("Projectile", require "game.def.projectile.projectile_def")
defs.register("Dummy", {
    name = "Dummy",
    props = {
        { name = "hp", type = "number", sync = "all", default = 100 },
    },
    records = {},
    containers = {},
})

local function newEntity(id, x, y)
    local e = Entity.new(defs.get("Dummy"), id, "Dummy")
    e.x = x
    e.y = y
    return e
end

local function newProjectile(x, y, props, runtime)
    local p = Entity.new(defs.get("Projectile"), 1000, "Projectile")
    p:set("x", x)
    p:set("y", y)
    if props then
        for k, v in pairs(props) do p:set(k, v) end
    end
    rawset(p, "runtime", runtime)
    return p
end

local function makeCell(entities)
    local removed = {}
    local cell = {
        entities = entities,
        removed = removed,
        removeEntity = function(_, e) removed[e.id] = true end,
        findByRealId = function(_, realId)
            for _, e in pairs(entities) do
                if e:getRealId() == realId then return e end
            end
        end,
    }
    for _, e in pairs(entities) do e.cell = cell end

    local spatial = SpatialIndex.new(60, 200, 200)
    for _, e in pairs(entities) do
        spatial:enter(e, e.x, e.y)
    end
    cell.spatial = spatial

    return cell
end

-- 1) homing: 命中返回 destroy
local hitData1
local owner = newEntity(1, 0, 0)
local targetA = newEntity(2, 10, 0)
local p1 = newProjectile(0, 0, { targetId = 2, speed = 100, range = 50, hitRadius = 2 }, {
    movement = "homing",
    onHit = function(_, targets, x, y)
        hitData1 = { targets = targets, x = x, y = y }
        return "destroy"
    end,
})
local cell1 = makeCell({ [owner.id] = owner, [targetA.id] = targetA, [p1.id] = p1 })
p1:setupComponents(p1.def.cellComponents)
local move1 = p1:getComponent("projectile")
while not move1.destroyed do move1:onTick(0.01) end

assert(hitData1, "homing hit callback missing")
assert(#hitData1.targets == 1, "homing should hit exactly one target")
assert(hitData1.targets[1] == targetA, "homing target mismatch")
assert(cell1.removed[p1.id], "homing should destroy after onHit returns destroy")
assert(targetA:get("hp") == 100, "component must not apply damage by itself")

-- 2) linear: 命中多个范围内候选, onHit 返回 keep
local hitData2
local dirTargetA = newEntity(3, 4, 0)
local dirTargetB = newEntity(4, 4, 2)
local p2 = newProjectile(0, 0, { dir = 0, speed = 10, range = 40, hitRadius = 5 }, {
    movement = "linear",
    onHit = function(_, targets, x, y)
        hitData2 = { targets = targets, x = x, y = y }
        return "keep"
    end,
})
local cell2 = makeCell({ [dirTargetA.id] = dirTargetA, [dirTargetB.id] = dirTargetB, [p2.id] = p2 })
p2:setupComponents(p2.def.cellComponents)
local move2 = p2:getComponent("projectile")
while not move2.destroyed do move2:onTick(0.1) end

assert(hitData2, "linear hit callback missing")
assert(#hitData2.targets >= 2, "linear should hit multiple targets in radius")

-- 3) linear: 超距销毁
local p3Hits = 0
local p3 = newProjectile(0, 0, { dir = 0, speed = 20, range = 15, hitRadius = 3 }, {
    movement = "linear",
    onHit = function()
        p3Hits = p3Hits + 1
        return "keep"
    end,
})
local cell3 = makeCell({ [99] = newEntity(99, 4, 0), [p3.id] = p3 })
p3:setupComponents(p3.def.cellComponents)
local move3 = p3:getComponent("projectile")
local guard = 0
while not move3.destroyed and guard < 200 do
    guard = guard + 1
    move3:onTick(0.1)
end

assert(cell3.removed[p3.id], "linear projectile should destroy after range")
print("PASS test_projectile")
