-- server/test/test_projectile.lua
-- 投掷物行为测试:
-- 1) targetId 模式 -> 追踪单一目标, hit 事件带 targetId
-- 2) dir 模式 -> 按方向前进, 碰撞半径检测多个目标, hit 事件带 targets
-- 3) projectile_effects 按投掷物 damage/damageType 结算伤害

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local Entity = require "tinyworld.entity.entity"

defs.register("Projectile", require "game.def.projectile.projectile_def")
defs.register("Dummy", {
    name = "Dummy",
    props = {
        { name = "hp", type = "number", sync = "all", default = 100 },
    },
    records = {},
    containers = {},
})

local function newEntity(id, hp, x, y)
    local e = Entity.new(defs.get("Dummy"), id, "Dummy")
    e.clientId = id
    if hp ~= nil then e:set("hp", hp) end
    e.x = x
    e.y = y
    return e
end

local function newProjectile(x, y, info)
    local p = Entity.new(defs.get("Projectile"), 1000, "Projectile")
    p.clientId = 1000
    p:set("x", x)
    p:set("y", y)
    for k, v in pairs(info or {}) do p:set(k, v) end
    return p
end

local function makeCell(entities)
    local removed = {}
    local function remove(c, e) removed[e.id] = true end
    local cell = { entities = entities, removeEntity = remove, removed = removed }
    for _, e in pairs(entities) do e.cell = cell end
    return cell
end

local function tickUntilDestroyed(p, dt)
    local move = p:getComponent("projectile_move")
    local guard = 0
    while not move.destroyed and guard < 1000 do
        guard = guard + 1
        move:onTick(dt)
    end
end

-- 1) 追踪型: 只击中一个目标
local owner = newEntity(1, 100, 0, 0)
local targetA = newEntity(2, 100, 10, 0)
local targetB = newEntity(3, 100, 10, 2)
local p1 = newProjectile(0, 0, { targetId = 2, speed = 10, range = 50, hitRadius = 2 })
local cell1 = makeCell({ [owner.id] = owner, [targetA.id] = targetA, [targetB.id] = targetB, [p1.id] = p1 })
p1:setupComponents(p1.def.cellComponents)
print("setup components tracking")
local hit1
p1:on("projectile_hit", function(_, d) hit1 = d end)
local move1 = p1:getComponent("projectile_move")
assert(move1, "projectile_move component missing")
while not move1.destroyed do move1:onTick(0.1) end
assert(hit1, "tracking hit event missing")
assert(hit1.targetId == 2, "tracking should hit single target")
assert(#hit1.targets == 0, "tracking targets should be empty")

-- 2) 方向型: 沿途碰撞目标
local dTargetA = newEntity(4, 100, 4, 0)
local dTargetB = newEntity(5, 100, 4, 2)
local dTargetFar = newEntity(6, 100, 50, 0)
local p2 = newProjectile(0, 0, { targetId = nil, dir = 0, speed = 10, range = 40, hitRadius = 5 })
local cell2 = makeCell({ [dTargetA.id] = dTargetA, [dTargetB.id] = dTargetB, [dTargetFar.id] = dTargetFar, [p2.id] = p2 })
p2:setupComponents(p2.def.cellComponents)
local hit2
p2:on("projectile_hit", function(_, d) hit2 = d end)
local move2 = p2:getComponent("projectile_move")
while not move2.destroyed do move2:onTick(0.1) end
assert(hit2, "directional hit event missing")
assert(#hit2.targets >= 2, "directional should detect targets in radius, got " .. #hit2.targets)

-- 3) effects: 伤害由 projectile_effects 结算
local owner3 = newEntity(7, 100, 0, 0)
local victim = newEntity(8, 100, 10, 0)
local p3 = newProjectile(0, 0, { targetId = 8, speed = 100, range = 20, hitRadius = 2, damage = 30, ownerId = 7 })
local cell3 = makeCell({ [owner3.id] = owner3, [victim.id] = victim, [p3.id] = p3 })
p3:setupComponents(p3.def.cellComponents)
local move3 = p3:getComponent("projectile_move")
while not move3.destroyed do move3:onTick(0.01) end
assert(victim:get("hp") == 70, ("victim hp=%d expected 70"):format(victim:get("hp")))

print("PASS test_projectile")
