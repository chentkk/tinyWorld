-- server/test/test_combat_entity.lua
-- 通用战斗实体(Projectile 新语义)使用层接口验收:
--   1. 静止 Aura + onIntervalThink: 每隔 tickInterval 造成 tickDamage, duration 到期销毁
--   2. movement="none" 不走碰撞
--   3. selectTarget / onHit / onDestroy 回调正常触发
-- 组件不做伤害的旧约束仍然成立(通过 manager 包装内置 damage 才产生伤害)。

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local Entity = require "tinyworld.entity.entity"
local SpatialIndex = require "tinyworld.app.cellapp.space.spatial_index"
local projectileManager = require "tinyworld.combat.projectile_manager"

defs.register("Projectile", require "game.def.projectile.projectile_def")
defs.register("Dummy", {
    name = "Dummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
        { name = "hp", type = "number", sync = "all", default = 100 },
    },
    records = {},
    containers = {},
})

local function newDummy(id, x, y, hp)
    local e = Entity.new(defs.get("Dummy"), id, "Dummy")
    e.x, e.y = x, y
    e:set("hp", hp or 100)
    return e
end

-- mock cell + host, 让 source:spawnProjectile 创建真实 Projectile 实体并挂 runtime
local function makeCell()
    local entities = {}
    local removed = {}
    local seq = 0
    local spatial = SpatialIndex.new(60, 200, 200)
    local cell = {
        entities = entities,
        removed = removed,
        space = { id = "main" },
        spatial = spatial,
        key = function() return "0:0" end,
        removeEntity = function(_, e) removed[e.id] = true end,
        findByRealId = function(_, rid)
            for _, e in pairs(entities) do
                if e:getRealId() == rid then return e end
            end
        end,
    }
    function cell:spawnEntity(kind, data, baseApp)
        assert(self.host and self.host.spawn_entity, "mock cell host needs spawn_entity")
        return self.host.spawn_entity(self.space.id, self:key(), kind, data, baseApp)
    end

    function cell:spawnProjectile(kind, data)
        assert(self.host and self.host.spawn_projectile, "mock cell host needs spawn_projectile")
        return self.host.spawn_projectile(self.space.id, self:key(), kind, data, nil)
    end

    cell.host = {
        spawn_entity = function(spaceId, cellKey, kind, data, baseApp)
            return cell:spawnLocalEntity(kind, data)
        end,
        spawn_projectile = function(spaceId, cellKey, kind, data, baseApp)
            return cell:spawnLocalEntity(kind or "Projectile", data)
        end,
    }

    -- 供上面两个 mock 命令使用
    function cell:spawnLocalEntity(kind, data)
        seq = seq + 1
        local p = Entity.new(defs.get(kind or "Projectile"), 8000 + seq, kind or "Projectile")
        p:set("x", data.props.x)
        p:set("y", data.props.y)
        for k, v in pairs(data.props) do
            if k ~= "x" and k ~= "y" then p:set(k, v) end
        end
        p.ability = data.ability
        rawset(p, "runtime", data.runtime)
        p.cell = cell
        p.space = { cells = { cell } }
        entities[p.id] = p
        spatial:enter(p, p.x, p.y)
        p:setupComponents(p.def.cellComponents)
        return { entityId = p.id }
    end
    return cell, entities, removed
end

-- ============ 场景 1: 静止毒液 ============
do
    local cell, entities, removed = makeCell()
    local caster = newDummy(1, 0, 0, 100)
    caster.cell = cell
    entities[caster.id] = caster

    local victim = newDummy(2, 10, 0, 100)  -- 在 areaRadius 10? 距离 10, 恰好
    victim.cell = cell
    entities[victim.id] = victim
    cell.spatial:enter(caster, caster.x, caster.y)
    cell.spatial:enter(victim, victim.x, victim.y)

    local ticks = {}
    local ok = projectileManager.Create({
        Source = caster,
        Ability = { GetAbilityName = function() return "ability_toxic_pool" end },
        movement = "none",
        x = 5, y = 0,
        duration = 0.5,
        tickInterval = 0.2,
        areaRadius = 10,
        tickDamage = { amount = 5, type = require("tinyworld.combat.damage").DAMAGE_TYPE.MAGICAL },
        onIntervalThink = function(_, targets, tickIndex)
            ticks[#ticks + 1] = { n = #targets, tickIndex = tickIndex }
        end,
    })
    assert(ok and ok.entityId, "spawn failed")

    local p = entities[ok.entityId]
    local comp = p:getComponent("projectile")
    for i = 1, 10 do
        if comp.destroyed then break end
        comp:onTick(0.1)
    end

    assert(comp.destroyed, "poison pool should expire by duration")
    assert(#ticks == 2, "expected 2 interval ticks over 0.5s")
    assert(ticks[1].n == 1 and ticks[1].tickIndex == 0, "tick0 should see victim")
    assert(victim:get("hp") == 90, "victim should take 2x5 damage")
    print("PASS combat_entity-static-pool")
end

-- ============ 场景 2: homing + selectTarget 重选 ============
do
    local cell, entities, _ = makeCell()
    local caster = newDummy(1, 0, 0, 100)
    caster.cell = cell
    entities[caster.id] = caster

    local dead = newDummy(2, 5, 0, 0)   -- 目标已死
    local alive = newDummy(3, 20, 0, 100)
    dead.cell, alive.cell = cell, cell
    entities[dead.id], entities[alive.id] = dead, alive
    cell.spatial:enter(caster, caster.x, caster.y)
    cell.spatial:enter(dead, dead.x, dead.y)
    cell.spatial:enter(alive, alive.x, alive.y)

    local selectedOld, selectedNew, hitList
    projectileManager.Create({
        Source = caster,
        Ability = { GetAbilityName = function() return "ability_spirit" end },
        movement = "homing",
        targetId = dead.id,
        speed = 100,
        range = 200,
        hitRadius = 2,
        duration = 10,
        selectTarget = function(_, oldId)
            selectedOld, selectedNew = oldId, alive:getRealId()
            return alive:getRealId()
        end,
        onHit = function(_, targets)
            hitList = targets
            return "destroy"
        end,
    })

    local spawnedId
    for id, e in pairs(entities) do
        if e.kind == "Projectile" then spawnedId = id end
    end
    local p = entities[spawnedId]
    local comp = p:getComponent("projectile")

    for i = 1, 10 do
        if comp.destroyed then break end
        comp:onTick(0.1)
    end

    assert(selectedOld == dead.id, "selectTarget got old target id")
    assert(selectedNew == alive.id, "selectTarget selected new target")
    assert(hitList and #hitList == 1 and hitList[1]:getRealId() == alive.id, "should hit reselected target")
    print("PASS combat_entity-homing-reselect")
end

print("ALL COMBAT ENTITY TESTS PASS")
