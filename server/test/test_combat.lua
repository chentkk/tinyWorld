-- server/test/test_combat.lua
-- 战斗 / 技能系统测试: 立即释放、施法时间、持续施法三种流程,
-- 以及伤害经属性(hp)自动同步的路径验证。

package.path = "./?.lua;./?/init.lua;" .. package.path

local entity = require "tinyworld.entity.entity"
local defs = require "tinyworld.entity.defs"
local caster = require "game.scripts.vscripts.combat.caster"
local combatDamage = require "game.scripts.vscripts.combat.damage"

defs.register("CombatDummy", {
    name = "CombatDummy",
    props = {
        { name = "hp", type = "number", sync = "all", persist = true, default = 500 },
        { name = "maxHp", type = "number", sync = "all", default = 500 },
    },
})

local unit = entity.Entity.new(defs.get("CombatDummy"), 1, "CombatDummy")
caster.apply(unit)
assert(unit.combatModifiers)

-- 能力: 无光之盾(施法时间 0.4s)
local shieldMod = require "game.scripts.vscripts.heroes.abaddon.ability_abaddon_aphotic_shield_lua"
local shield = shieldMod.ability_abaddon_aphotic_shield_lua.new(unit, {
    castPoint = 0.4, cooldown = 6, duration = 6, damageAbsorb = 110 })
table.insert(unit.abilities, shield)

local borrowedMod = require "game.scripts.vscripts.heroes.abaddon.ability_abaddon_borrowed_time_lua"
local borrowed = borrowedMod.ability_abaddon_borrowed_time_lua.new(unit, {
    castPoint = 0, cooldown = 40, channelTime = 3 })
table.insert(unit.abilities, borrowed)

-- 立即进入持续施法
assert(unit:castAbility(2, nil))
unit:updateCombat(0.1)
assert(borrowed.state == borrowed.state and borrowed.state == "channeling" or borrowed.state == "channeling")

-- 带施法时间: 施法中尚不产生 modifier
local target = entity.Entity.new(defs.get("CombatDummy"), 2, "CombatDummy")
caster.apply(target)
target.hp = 500
unit:castAbility(1, target)
unit:updateCombat(0.2)
assert(#target.combatModifiers == 0, "should not apply before cast point")

unit:updateCombat(0.3) -- 达到 castPoint 0.4 后开始
unit:updateCombat(0.1)
assert(#target.combatModifiers == 1, "shield modifier should apply after cast point")

-- 伤害结算: hp 属性自动变化, 并触发事件
local damaged = 0
target:on("on_damage", function(_, a, amount, t)
    damaged = amount
end)
combatDamage.dealDamage(unit, target, 80, combatDamage.DAMAGE_TYPE.MAGICAL)
assert(target:get("hp") == 420)
assert(damaged == 80)

print("PASS test_combat")
