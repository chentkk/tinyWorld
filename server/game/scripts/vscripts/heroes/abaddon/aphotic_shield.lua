-- game/scripts/vscripts/heroes/abaddon/aphotic_shield.lua
-- 无光之盾: 施法时间结束后为目标套盾, modifier 吸收伤害。

local Ability = require "tinyworld.combat.ability"
local Modifier = require "tinyworld.combat.modifier"

ability_aphotic_shield = Ability.extend("ability_aphotic_shield")
modifier_abaddon_aphotic_shield_lua = Modifier.extend("modifier_abaddon_aphotic_shield_lua")

function ability_aphotic_shield:OnSpellStart()
    local target = self:GetCursorTarget() or self:GetCaster()
    target:addModifier("modifier_abaddon_aphotic_shield_lua", self, {
        duration = tonumber(self:GetSpecialValueFor("duration")),
        absorb = tonumber(self:GetSpecialValueFor("damageAbsorb")),
    })
end

function modifier_abaddon_aphotic_shield_lua:OnCreated(data)
    self.absorb = data.absorb
    self.absorbAmount = 0
    self.parent = self:GetParent()
end

function modifier_abaddon_aphotic_shield_lua:OnRefresh(data)
    self.absorb = data.absorb
    self.parent = self:GetParent()
end

function modifier_abaddon_aphotic_shield_lua:GetModifierIncomingDamage_Percentage(data)
    self.absorbAmount = self.absorbAmount + data.damage
    if self.absorbAmount > self.absorb then self:Destroy() end
    return -100
end

