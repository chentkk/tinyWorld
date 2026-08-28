-- game/scripts/vscripts/heroes/vampire/blood_harvest.lua
-- 血色收割: 对周围范围内目标造成一次直接伤害并附加持续掉血 modifier,
-- 同时为施法者回复生命值。

local Ability = require "tinyworld.combat.ability"
local Modifier = require "tinyworld.combat.modifier"
local combatDamage = require "tinyworld.combat.damage"

ABILITY_BLOOD_HARVEST = "ability_blood_harvest"
ABILITY_BLOOD_HARVEST_BLEED = "modifier_blood_harvest_bleed"

ability_blood_harvest = Ability.extend("ability_blood_harvest")
modifier_blood_harvest_bleed = Modifier.extend("modifier_blood_harvest_bleed")

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
    local healAmount = tonumber(self:GetSpecialValueFor("healAmount")) or 80
    local bleedDuration = tonumber(self:GetSpecialValueFor("bleedDuration")) or 6
    local tickInterval = tonumber(self:GetSpecialValueFor("tickInterval")) or 1
    local tickDamage = tonumber(self:GetSpecialValueFor("tickDamage")) or 15

    local hitCount = 0
    for _, target in ipairs(self:collectTargetsInRadius()) do
        combatDamage.dealDamage(caster, target, damage,
            combatDamage.DAMAGE_TYPE.MAGICAL, self)

        target:addModifier(ABILITY_BLOOD_HARVEST_BLEED, self, {
            duration = bleedDuration,
            intervalThink = tickInterval,
            damagePerTick = tickDamage,
        })
        hitCount = hitCount + 1
    end

    combatDamage.dealHeal(caster, caster,
        healAmount + hitCount * (tonumber(self:GetSpecialValueFor("healPerHit")) or 0),
        combatDamage.HEAL_TYPE.HEAL, self)
end

function modifier_blood_harvest_bleed:OnCreated(data)
    self.damagePerTick = tonumber(data.damagePerTick) or 15
    self.intervalThink = tonumber(data.intervalThink) or 1
    self.parent = self:GetParent()
end

function modifier_blood_harvest_bleed:OnRefresh(data)
    self.damagePerTick = tonumber(data.damagePerTick) or self.damagePerTick
    self.intervalThink = tonumber(data.intervalThink) or self.intervalThink
    self.parent = self:GetParent()
end

function modifier_blood_harvest_bleed:OnIntervalThink()
    local target = self:GetParent()
    local caster = self:GetCaster()
    if not target or not caster then return end

    combatDamage.dealDamage(caster, target, self.damagePerTick,
        combatDamage.DAMAGE_TYPE.MAGICAL, self:GetAbility())
end

