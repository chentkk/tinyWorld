-- server/test/test_combat.lua
-- 战斗 / 技能系统测试: 立即释放、施法时间、持续施法三种流程,
-- 以及伤害经属性(hp)自动同步的路径验证。

package.path = "./?.lua;./?/init.lua;" .. package.path

local Entity = require "tinyworld.entity.entity"
local defs = require "tinyworld.entity.defs"
local caster = require "tinyworld.combat.unit"
local combatDamage = require "tinyworld.combat.damage"

defs.register("CombatDummy", {
    name = "CombatDummy",
    props = {
        { name = "hp", type = "number", sync = "all", persist = true, default = 500 },
        { name = "maxHp", type = "number", sync = "all", default = 500 },
    },
})

local unit = Entity.new(defs.get("CombatDummy"), 1, "CombatDummy")
caster.apply(unit)
assert(unit.combatApplied)

-- 注册能力工厂(与 cellapp init 一致), 再用 unit:loadAbilities 创建能力
require "game.scripts.vscripts.abilities"

unit:loadAbilities({
    "ability_aphotic_shield",
    "ability_borrowed_time",
    "ability_mist_coil",
    "ability_curse_of_avernus",
})

local shield = unit.abilities[1]
local borrowed = unit.abilities[2]
local mistCoil = unit.abilities[3]
local curse = unit.abilities[4]

-- 立即进入持续施法
assert(unit:castAbility(2, nil))
unit:updateCombat(0.1)
assert(borrowed.state == "channeling")

-- 带施法时间: 施法中尚不产生 modifier
local target = Entity.new(defs.get("CombatDummy"), 2, "CombatDummy")
caster.apply(target)
target.hp = 500
unit:castAbility(1, target)
unit:updateCombat(0.2)
assert(#target.modifiers == 0, "should not apply before cast point")

unit:updateCombat(0.3) -- 达到 castPoint 0.4 后开始
unit:updateCombat(0.1)
assert(#target.modifiers == 1, "shield modifier should apply after cast point")

-- 先摧毁盾, 再验证伤害结算: hp 属性自动变化, 并触发事件
target.modifiers[1]:destroy()
assert(#target.modifiers == 0)
local damaged = 0
target:on("combat_damage", function(_, a, amount, t)
    damaged = amount
end)
combatDamage.dealDamage(unit, target, 80, combatDamage.DAMAGE_TYPE.MAGICAL)
assert(target:get("hp") == 420)
assert(damaged == 80)

-- 立即释放: 迷雾缠绕造成 90 点魔法伤害
unit:castAbility(3, target)
unit:updateCombat(0.2)
assert(target:get("hp") == 330)

-- modifier 增加 / 移除事件可驱动底层同步(buff view)
local addedNames = {}
target:on("combat_modifier_add", function(_, name, duration, stack)
    addedNames[#addedNames + 1] = name
end)
shield.cooldownLeft = 0
shield.state = "ready"
unit:castAbility(1, target)
unit:updateCombat(0.5) -- 超过 castPoint
assert(#target.modifiers == 1)
assert(addedNames[1] == "modifier_abaddon_aphotic_shield_lua")

print("PASS test_combat")
