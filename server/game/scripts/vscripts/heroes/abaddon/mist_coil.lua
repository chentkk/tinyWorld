-- game/scripts/vscripts/heroes/abaddon/mist_coil.lua
-- 迷雾缠绕: 立即对目标造成魔法伤害, 自身承受纯伤害。

local abilityMod = require "tinyworld.combat.ability"
local combatDamage = require "tinyworld.combat.damage"
local M = {}

M.ability_mist_coil = abilityMod.Ability.extend("ability_mist_coil")

function M.ability_mist_coil:OnSpellStart()
    local target = self.target
    if not target then return end

    combatDamage.dealDamage(self.caster, target, tonumber(self.data.damage) or 90,
        combatDamage.DAMAGE_TYPE.MAGICAL, self)

    local selfDamage = tonumber(self.data.selfDamage) or 0
    if selfDamage > 0 then
        combatDamage.dealDamage(self.caster, self.caster, selfDamage,
            combatDamage.DAMAGE_TYPE.PURE, self)
    end
end

return M
