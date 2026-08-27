-- game/scripts/vscripts/heroes/abaddon/aphotic_shield.lua
-- 无光之盾: 施法时间结束后为目标套盾, modifier 吸收伤害。

local Ability = require "tinyworld.combat.ability"
local Modifier = require "tinyworld.combat.modifier"

local ability_aphotic_shield = Ability.extend("ability_aphotic_shield")
local modifier_abaddon_aphotic_shield_lua = Modifier.extend("modifier_abaddon_aphotic_shield_lua")

function ability_aphotic_shield:OnSpellStart()
    local target = self.target or self.caster
    target:addModifier(modifier_abaddon_aphotic_shield_lua.new(
        self.caster, self, tonumber(self.data.duration)))
end

function modifier_abaddon_aphotic_shield_lua:OnCreated(params)
    self.absorb = tonumber(self.ability.data.damageAbsorb) or 0
end

function modifier_abaddon_aphotic_shield_lua:OnRefresh(params)
    self.absorb = tonumber(self.ability.data.damageAbsorb) or self.absorb
end

function modifier_abaddon_aphotic_shield_lua:OnDamageReceived(attacker, amount, damageType)
    if self.absorb <= 0 then return amount end
    local blocked = math.min(self.absorb, amount)
    self.absorb = self.absorb - blocked
    if self.absorb <= 0 then self:destroy() end
    return amount - blocked
end

return {
    ability_aphotic_shield = ability_aphotic_shield,
    modifier_abaddon_aphotic_shield_lua = modifier_abaddon_aphotic_shield_lua,
}
