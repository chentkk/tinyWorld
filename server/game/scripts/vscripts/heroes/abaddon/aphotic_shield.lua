-- game/scripts/vscripts/heroes/abaddon/aphotic_shield.lua
-- 无光之盾: 施法时间结束后为目标套盾, modifier 吸收伤害。
-- modifier 增删由底层同步(buff view), 这里不处理网络。

local abilityMod = require "tinyworld.combat.ability"
local modifierMod = require "tinyworld.combat.modifier"
local M = {}

M.ability_aphotic_shield = abilityMod.extend("ability_aphotic_shield")

function M.ability_aphotic_shield:OnSpellStart()
    local target = self.target or self.caster
    target:addModifier(M.modifier_abaddon_aphotic_shield_lua.new(self.caster, self, tonumber(self.data.duration)))
end

M.modifier_abaddon_aphotic_shield_lua = modifierMod.extend("modifier_abaddon_aphotic_shield_lua")

function M.modifier_abaddon_aphotic_shield_lua:OnCreated(params)
    self.absorb = tonumber(self.ability.data.damageAbsorb) or 0
end

function M.modifier_abaddon_aphotic_shield_lua:OnRefresh(params)
    self.absorb = tonumber(self.ability.data.damageAbsorb) or self.absorb
end

function M.modifier_abaddon_aphotic_shield_lua:OnDamageReceived(attacker, amount, damageType)
    if self.absorb <= 0 then return amount end
    local blocked = math.min(self.absorb, amount)
    self.absorb = self.absorb - blocked
    if self.absorb <= 0 then self:destroy() end
    return amount - blocked
end

return M
