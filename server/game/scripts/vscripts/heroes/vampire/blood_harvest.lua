-- game/scripts/vscripts/heroes/vampire/blood_harvest.lua
-- 血色收割: 对周围目标造成一次直接伤害; 持续掉血 modifier 待重新设计后实现。

local Ability = require "tinyworld.combat.ability"
local combatDamage = require "tinyworld.combat.damage"

ability_blood_harvest = Ability.extend("ability_blood_harvest")

-- 以施法者为中心收集技能范围内的目标(不含施法者自身)
function ability_blood_harvest:collectTargetsInRadius()
    local caster = self:GetCaster()
    if not caster then return {} end

    local radius = tonumber(self:GetSpecialValueFor("radius")) or 80
    local radius2 = radius * radius

    local targets = {}
    for _, candidate in pairs(caster.cell and caster.cell.entities or {}) do
        if candidate ~= caster and candidate.def and candidate.id ~= caster.id then
            local dx = (candidate.x or 0) - (caster.x or 0)
            local dy = (candidate.y or 0) - (caster.y or 0)
            if dx * dx + dy * dy <= radius2 then
                targets[#targets + 1] = candidate
            end
        end
    end
    return targets
end

function ability_blood_harvest:OnSpellStart()
    local caster = self:GetCaster()
    if not caster then return end

    local damage = tonumber(self:GetSpecialValueFor("damage")) or 120
    for _, target in ipairs(self:collectTargetsInRadius()) do
        combatDamage.dealDamage(caster, target, damage,
            combatDamage.DAMAGE_TYPE.MAGICAL, self)
    end
end

return ability_blood_harvest
