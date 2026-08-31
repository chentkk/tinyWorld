-- server/test/test_projectile.lua
-- 投掷物运动与事件测试: 直线、追踪、命中、事件只发不结算。

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local Entity = require "tinyworld.entity.entity"

defs.register("Projectile", require "game.def.projectile.projectile_def")

local function newProjectile(id, x, y, targetId)
    local p = Entity.new(defs.get("Projectile"), id, "Projectile")
    p:set("x", x)
    p:set("y", y)
    p:set("targetId", targetId)
    return p
end

local hits = {}
local projectile = newProjectile(1, 0, 0, nil)
local target = Entity.new(defs.get("Projectile"), 2, "Projectile")
target.x = 10
target.y = 0
target.clientId = 2

local removed = {}
local cell = {
    entities = { [projectile.id] = projectile, [target.id] = target },
    removeEntity = function(_, e)
        removed[e.id] = true
    end,
}
projectile.cell = cell
projectile:on("projectile_hit", function(_, data)
    hits[#hits + 1] = data
end)

projectile:addComponent("projectile_move", require "game.components.projectile_move")

-- 追踪目标
projectile:set("targetId", 2)
projectile:getComponent("projectile_move"):onTick(0.5)
assert(projectile.x > 0, "projectile should move toward target")

while not removed[projectile.id] do
    projectile:getComponent("projectile_move"):onTick(0.1)
    if projectile:getComponent("projectile_move").destroyed and removed[projectile.id] then break end
end

assert(hits[1], "projectile_hit event missing")
assert(hits[1].ownerId == nil, "hit event should not force damage/owner semantics")
assert(hits[1].targetId == 2, "hit event should carry targetId")
assert(removed[projectile.id], "projectile should be destroyed after hit")

print("PASS test_projectile")
