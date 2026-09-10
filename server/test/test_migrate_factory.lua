-- server/test/test_migrate_factory.lua
-- 迁移后容器子对象必须恢复为带行为的实例(工厂), 而不是退化成纯数据 Object:
--   abilities_view / modifiers_view 的子对象带 update 等行为, 若迁移后变为
--   普通 Object, CombatAgent:onTick 调用 mod:update / ab:update 会直接抛错,
--   进而杀掉 cellapp 的 tick 循环。
-- 本测试锁定 Container childFactory 机制。

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local abilityLoader = require "tinyworld.combat.ability_loader"
local Ability = require "tinyworld.combat.ability"
local Modifier = require "tinyworld.combat.modifier"
local modifierManager = require "tinyworld.combat.modifier_manager"
local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LocalSpace = require "tinyworld.app.cellapp.space.local_space"
local RealEntity = require "tinyworld.app.cellapp.entities.real_entity"

-- 测试用工厂: 提供 Ability / Modifier 实例, 走与线上相同的 factory 模块。
local FakeAbility = Ability.extend("fake_ability")
local function fakeAbilityFactory(caster, name, schema)
    return FakeAbility.new(caster, {
        name = name, AbilityCooldown = 1, AbilityCastPoint = 0, intervalThink = 0,
    }, schema)
end
_G.fake_ability = FakeAbility

-- 具体子类名即 modifier 名(基类用 self.name 作为 GetModifierName)
local FakeModifier = Modifier.extend("fake_modifier")
FakeModifier.tickCount = 0
function FakeModifier:OnIntervalThink() FakeModifier.tickCount = FakeModifier.tickCount + 1 end
_G.fake_modifier = FakeModifier

local avDef = require "game.def.container.abilities_view_def"
local mvDef = require "game.def.container.modifiers_view_def"

defs.register("CombatDummy", {
    name = "CombatDummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
        { name = "hp", type = "number", sync = "all", default = 100 },
    },
    records = {},
    containers = { avDef, mvDef },
    cellComponents = { "tinyworld.combat.combat_agent" },
    cellOpenViews = { "abilities_view", "modifiers_view" },
})

-- 必须在构造实体前注册 abilityFactory(线上由 cellapp init 完成)
abilityLoader.setAbilityFactory(fakeAbilityFactory)

local config = SpaceConfig.compile({ id = "facmv", width = 200, height = 100,
    aoiRange = 20, ghostRange = 40, cellSize = 100, minMigrateInterval = 0, hysteresis = 5 })
CellAllocator.distribute(config, { 1 })
local app = { appId = 1, time = 100, seq = 0, spaceConfig = config }
function app:now() return self.time end
function app:sendToClient() end
function app:notifyEntityMoved() end
local space = LocalSpace.new(app)
for _, c in ipairs(config.cells) do space:addLocalCell(c) end
local cellA = space:getCell("0:0")
local cellB = space:getCell("1:0")

local real = RealEntity.new(defs.get("CombatDummy"), 7001, "CombatDummy", space, cellA)
real.props:load({ x = 20, y = 50 })
cellA:addEntity(real)
real:openViews(real.def.cellOpenViews)
real:setupComponents(real.def.cellComponents)
real:onApplyCellData({ initData = { abilities = { "fake_ability" } } })
real:onCreate()

local ability = real:getContainer("abilities_view"):childrenList()[1]
assert(ability and ability:GetAbilityName() == "fake_ability", "ability should be live before migration")

local mod = FakeModifier.new(real, Modifier.buildParams(ability, { duration = 5 }),
    real:getContainer("modifiers_view").def.childSchema)
modifierManager.addModifier(real, mod, ability, { duration = 5 })
assert(real:getContainer("modifiers_view"):count() == 1, "modifier registered before migration")
local uidBefore = mod.uid

-- 触发迁移
real:set("x", 150)
cellA:tick(0)

local moved = cellB:get(7001)
assert(moved and moved.isReal, "real migrated to cellB")

-- abilities_view 子对象应恢复为带行为的 Ability
local ab2 = moved:getContainer("abilities_view"):childrenList()[1]
assert(ab2 and ab2.update, "ability must be a live instance after migration")
assert(ab2:GetAbilityName() == "fake_ability", "ability name restored")

-- modifiers_view 子对象应恢复为带行为的 Modifier, 且 uid 保持
local mods = moved:getContainer("modifiers_view"):childrenList()
assert(#mods == 1, "modifier restored after migration")
assert(mods[1].update, "modifier must be a live instance after migration")
assert(mods[1].uid == uidBefore, "modifier uid must be preserved for removal")
assert(mods[1].remaining == 5, "modifier remaining restored")

-- 迁移后 onTick 不能抛错(否则 cellapp tick 循环会被打断)
local ok, err = pcall(function() moved:onTick(0.1) end)
assert(ok, "onTick must not crash after migration: " .. tostring(err))

-- 工厂重建的 modifier 仍可正常移除
modifierManager.removeModifier(moved, mods[1])
assert(moved:getContainer("modifiers_view"):count() == 0, "modifier removal after migration")

-- ============ modifier 来源 ability / caster 不存在时仍可重建 ============
-- Modifier.fromData 只能依赖可序列化纯状态, 不得引用来源 ability / caster 对象。
do
    local view = moved:getContainer("modifiers_view")
    local mod2 = view:addFromData({
        id = 4242, name = "fake_modifier", stack = 2, duration = 10,
        remaining = 4, abilityName = "ability_that_no_longer_exists",
        casterId = 999999, intervalThink = 0, elapsed = 6,
    })
    assert(mod2 and mod2.update, "modifier must rebuild without source ability")
    assert(mod2:GetModifierName() == "fake_modifier", "modifier name restored")
    assert(mod2.uid == 4242, "modifier uid restored")
    assert(mod2.duration == 10 and mod2.elapsed == 6, "modifier state restored")
    -- 来源 caster 不存在 -> GetCaster 返回 nil, 不报错
    assert(mod2:GetCaster() == nil, "missing caster must resolve to nil, not error")
    -- update 正常推进
    mod2:update(0.1)
    assert(mod2.remaining == 3.9, "modifier update after rebuild")
    view:remove(4242)
end

-- ============ 迁移后 modifier 的 intervalThink 正常触发 ============
do
    -- 造一个带 intervalThink 的 modifier 并迁移, 验证迁移后仍按周期回调
    local mv = moved:getContainer("modifiers_view")
    local mod = mv:addFromData({
        id = 5555, name = "fake_modifier", stack = 1, duration = 100,
        remaining = 100, abilityName = "x", casterId = 0, intervalThink = 1, elapsed = 0,
    })
    local before = FakeModifier.tickCount
    -- 模拟 3.5 秒 tick (每次 dt=0.1)
    for _ = 1, 35 do mod:update(0.1) end
    assert(FakeModifier.tickCount - before == 3,
        "OnIntervalThink should fire ~intervalThink times after migration")
    assert(mod.remaining == 96.5, "remaining should advance after migration")
    mv:remove(5555)
end

print("PASS migrate-factory")
