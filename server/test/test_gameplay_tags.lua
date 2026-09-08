-- server/test/test_gameplay_tags.lua
-- 对象分类 tag 系统: def.tags 归一化 + Entity 查询 + projectile 目标筛选

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local Entity = require "tinyworld.entity.entity"
local SpatialIndex = require "tinyworld.app.cellapp.space.spatial_index"

defs.register("TagEnemy", {
    name = "TagEnemy",
    tags = { "unit", "enemy", "hostile" },
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
        { name = "hp", type = "number", sync = "all", default = 100 },
    },
    records = {},
    containers = {},
})

defs.register("TagProjectile", {
    name = "TagProjectile",
    tags = { "projectile", "not_targetable" },
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
    },
    records = {},
    containers = {},
})

-- 1) def.tags 归一化
local enemyDef = defs.get("TagEnemy")
assert(enemyDef.tags.enemy == true, "tags should be normalized")
assert(enemyDef.tags.unit == true)

local enemy = Entity.new(enemyDef, 1, "TagEnemy")
enemy.x, enemy.y = 10, 0

assert(enemy:hasTag("enemy"), "hasTag enemy")
assert(enemy:hasAnyTag({ "boss", "enemy" }), "hasAnyTag")
assert(enemy:hasAllTags({ "unit", "hostile" }), "hasAllTags")
assert(not enemy:hasTag("boss"), "no boss tag")

-- 2) projectile 不该选择 not_targetable 对象
local projDef = require "tinyworld.entity.defs"
defs.register("Projectile", require "game.def.projectile.projectile_def")
local p = Entity.new(defs.get("Projectile"), 1000, "Projectile")
p:set("x", 0); p:set("y", 0)
rawset(p, "runtime", { movement = "none", onHit = function() return "keep" end })

local fakeCell = {
    entities = { [enemy.id] = enemy, [p.id] = p },
    removeEntity = function() end,
    findByRealId = function(_, rid)
        return fakeCell.entities[rid]
    end,
}
local spatial = SpatialIndex.new(60, 200, 200)
for _, e in pairs(fakeCell.entities) do
    e.cell = fakeCell
    spatial:enter(e, e.x, e.y)
end
fakeCell.spatial = spatial

p.cell = fakeCell
p:setupComponents(p.def.cellComponents)
local comp = p:getComponent("projectile")
assert(comp, "projectile component")

-- enemy 在 60 范围内且没有 not_targetable -> 应被选中
local hit = comp:targetsInRadius(30)
assert(#hit == 1 and hit[1] == enemy, "enemy should be targetable")

-- 构造一个带 projectile 标签的对象在范围内, 应被 not_targetable 过滤掉
local otherProjectile = Entity.new(defs.get("Projectile"), 1001, "Projectile")
otherProjectile:set("x", 5); otherProjectile:set("y", 0)
rawset(otherProjectile, "runtime", { movement = "none" })
otherProjectile.cell = fakeCell
fakeCell.entities[otherProjectile.id] = otherProjectile
spatial:enter(otherProjectile, otherProjectile.x, otherProjectile.y)

hit = comp:targetsInRadius(30)
assert(#hit == 1, "other projectile must not be selected")
assert(hit[1] == enemy, "only real targetable object should be selected")

print("PASS test_gameplay_tags")
