-- server/test/test_blood_harvest.lua
-- 新技能 ability_blood_harvest 的核心逻辑验证:
-- 1) 范围目标受到一次直接伤害
-- 2) 目标被附加持续掉血 modifier(intervalThink)
-- 3) 施法者自身回血

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local Entity = require "tinyworld.entity.entity"
local combatUnit = require "tinyworld.combat.unit"
local combatDamage = require "tinyworld.combat.damage"

defs.register("BloodDummy", {
    name = "BloodDummy",
    props = {
        { name = "hp", type = "number", sync = "all", persist = true, default = 500 },
        { name = "maxHp", type = "number", sync = "all", persist = true, default = 500 },
    },
    containers = {
        (require "game.def.container.modifiers_view_def"),
        (require "game.def.container.abilities_view_def"),
    },
})

-- 注册技能工厂(与 cellapp 一致)
require "game.scripts.vscripts.abilities"

local function newUnit(id, hp)
    local unit = Entity.new(defs.get("BloodDummy"), id, "BloodDummy")
    unit:getContainer("modifiers_view"):openView("modifiers")
    unit:getContainer("abilities_view"):openView("abilities")
    combatUnit.apply(unit)
    unit:set("hp", hp)
    return unit
end

local function abilitiesOf(unit)
    return unit:getContainer("abilities_view"):childrenList()
end

local caster = newUnit(1, 300)
local near = newUnit(2, 500)
local far = newUnit(3, 500)

-- 伪造 cell 上下文: 技能按坐标收集范围内目标
local cell = { entities = { [caster.id] = caster, [near.id] = near, [far.id] = far } }
caster.cell = cell
caster.x, caster.y = 0, 0
near.x, near.y = 40, 0    -- radius 80 内
far.x, far.y = 200, 0     -- radius 80 外

caster:loadAbilities({ "ability_blood_harvest" })
local ab = abilitiesOf(caster)[1]
assert(ab, "ability_blood_harvest not loaded")
assert(ab:GetAbilityName() == "ability_blood_harvest")

-- 平铺到施法完成(castPoint 0.3)
ab:cast(nil)
caster:updateCombat(0.3)
caster:updateCombat(0.1)

-- 直接伤害: 120
assert(near:get("hp") == 500 - 120, ("near hp=%d expected 380"):format(near:get("hp")))
-- 范围外目标不受影响
assert(far:get("hp") == 500, "far target should not take damage")
-- 施法者回血: 300 + 80
assert(caster:get("hp") == 300 + 80, ("caster hp=%d expected 380"):format(caster:get("hp")))

-- 持续掉血 modifier: 每 tick 15 点
assert(near:hasModifier("modifier_blood_harvest_bleed"), "bleed modifier missing")
assert(far:hasModifier("modifier_blood_harvest_bleed") == nil, "far target should not be bled")

-- 主动触发 intervalThink 验证掉落逻辑
local bleed = near:hasModifier("modifier_blood_harvest_bleed")
bleed:OnIntervalThink()
assert(near:get("hp") == 380 - 15, ("near hp after tick=%d expected 365"):format(near:get("hp")))

print("PASS test_blood_harvest")
