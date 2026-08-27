-- game/scripts/vscripts/heroes/abaddon/mist_coil.lua
-- 迷雾缠绕: 立即对目标造成魔法伤害, 自身承受纯伤害。

local Ability = require "tinyworld.combat.ability"
local combatDamage = require "tinyworld.combat.damage"

ability_mist_coil = Ability.extend("ability_mist_coil")

function ability_mist_coil:OnSpellStart()
    local target = self.target
    if not target then return end

    combatDamage.dealDamage(self.caster, target, tonumber(self:GetSpecialValueFor("damage")) or 90,
        combatDamage.DAMAGE_TYPE.MAGICAL, self)

    local selfDamage = tonumber(self:GetSpecialValueFor("selfDamage")) or 0
    if selfDamage > 0 then
        combatDamage.dealDamage(self.caster, self.caster, selfDamage,
            combatDamage.DAMAGE_TYPE.PURE, self)
    end
end

