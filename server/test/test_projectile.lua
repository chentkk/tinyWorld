-- server/test/test_projectile.lua
-- 投掷物运动与命中回调测试:
--   * targetId: 追踪命中单一目标
--   * dir: 直线前进, 按 hitRadius 检测多个目标
--   * 命中只回调 ability:OnProjectileHit, 组件不做伤害

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local Entity = require "tinyworld.entity.entity"

defs.register("Projectile", require "game.def.projectile.projectile_def")
defs.register("Dummy", {
    name = "Dummy",
    props = { { name = "hp", type = "number", sync = "all", default = 100 } },
    records = {},
    containers = {},
})

local function newEntity(id, x, y)
    local e = Entity.new(defs.get("Dummy"), id, "Dummy")
    e.clientId = id
    e.x = x
    e.y = y
    return e
end

local function newProjectile(x, y, props, ability)
    local p = Entity.new(defs.get("Projectile"), 1000, "Projectile")
    p.clientId = 1000
    p:set("x", x)
    p:set("y", y)
    if props then
        for k, v in pairs(props) do p:set(k, v) end
    end
    p.ability = ability
    return p
end

local function makeCell(entities)
    local removed = {}
    local cell = {
        entities = entities,
        removed = removed,
        removeEntity = function(_, e) removed[e.id] = true end,
    }
    for _, e in pairs(entities) do e.cell = cell end
    return cell
end

-- 1) 追踪型: 回调只收到单一目标, path 需要不断 tick
local hitData1
local fakeAbility1 = {
    OnProjectileHit = function(_, targets, x, y)
        hitData1 = { targets = targets, x = x, y = y }
    end,
}

local owner = newEntity(1, 0, 0)
local targetA = newEntity(2, 10, 0)
local p1 = newProjectile(0, 0, { targetId = 2, speed = 100, range = 50, hitRadius = 2 }, fakeAbility1)
local cell1 = makeCell({ [owner.id] = owner, [targetA.id] = targetA, [p1.id] = p1 })
p1:setupComponents(p1.def.cellComponents)
local move1 = p1:getComponent("projectile")
while not move1.destroyed do move1:onTick(0.01) end

assert(hitData1, "tracking hit callback missing")
assert(#hitData1.targets == 1, "tracking should hit exactly one target")
assert(hitData1.targets[1] == targetA, "tracking target mismatch")
assert(targetA:get("hp") == 100, "component must not apply damage automatically")

-- 2) 方向型: 回调收到碰撞范围内多个目标
local hitData2
local fakeAbility2 = {
    OnProjectileHit = function(_, targets, x, y)
        hitData2 = { targets = targets, x = x, y = y }
    end,
}

local dirTargetA = newEntity(3, 4, 0)
local dirTargetB = newEntity(4, 4, 2)
local p2 = newProjectile(0, 0, { targetId = nil, dir = 0, speed = 10, range = 40, hitRadius = 5 }, fakeAbility2)
local cell2 = makeCell({ [dirTargetA.id] = dirTargetA, [dirTargetB.id] = dirTargetB, [p2.id] = p2 })
p2:setupComponents(p2.def.cellComponents)
local move2 = p2:getComponent("projectile")
while not move2.destroyed do move2:onTick(0.1) end

assert(hitData2, "directional hit callback missing")
assert(#hitData2.targets >= 2, "directional should hit multiple targets")

-- 3) 穿透型: 命中后不销毁, 继续飞行直到超距; 同一目标只命中一次
local hitData3 = {}
local fakeAbility3 = {
    OnProjectileHit = function(_, targets, x, y)
        hitData3[#hitData3 + 1] = targets
    end,
}

local pierceTargetA = newEntity(5, 4, 0)
local pierceTargetB = newEntity(6, 9, 0)
local p3 = newProjectile(0, 0, {
    targetId = nil, dir = 0, speed = 20, range = 15, hitRadius = 3,
    pierce = true,
}, fakeAbility3)
local cell3 = makeCell({ [pierceTargetA.id] = pierceTargetA, [pierceTargetB.id] = pierceTargetB, [p3.id] = p3 })
p3:setupComponents(p3.def.cellComponents)
local move3 = p3:getComponent("projectile")
local guard = 0
while not move3.destroyed and guard < 100 do
    guard = guard + 1
    move3:onTick(0.1)
end

assert(#hitData3 >= 2, "pierce projectile should hit multiple distinct targets")
assert(cell3.removed[p3.id], "pierce projectile should eventually be destroyed after range")

print("PASS test_projectile")
