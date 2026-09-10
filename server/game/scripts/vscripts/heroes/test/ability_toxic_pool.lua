-- game/scripts/vscripts/heroes/test/ability_toxic_pool.lua
-- 示例: 一滩毒液。
-- 在目标点制造静止区域, 持续 6 秒, 每 1 秒对范围内敌人造成伤害。

local Ability = require "tinyworld.combat.ability"
local combatDamage = require "tinyworld.combat.damage"
local projectileManager = require "tinyworld.combat.projectile_manager"

ability_toxic_pool = Ability.extend("ability_toxic_pool")

function ability_toxic_pool:OnSpellStart()
    local caster = self:GetCaster()
    if not caster then return end

    local angle = caster:get("dir") or 0
    local dx = math.cos(angle)
    local dy = math.sin(angle)
    local x = caster.x + dx * 40
    local y = caster.y + dy * 40

    projectileManager.Create({
        Source = caster,
        Ability = self,
        movement = "none",
        x = x, y = y,
        duration = tonumber(self:GetSpecialValueFor("duration")) or 6,
        tickInterval = tonumber(self:GetSpecialValueFor("tickInterval")) or 1,
        areaRadius = tonumber(self:GetSpecialValueFor("areaRadius")) or 30,
        tickDamage = {
            amount = tonumber(self:GetSpecialValueFor("damage")) or 8,
            type = combatDamage.DAMAGE_TYPE.MAGICAL,
        },
    })
end

return ability_toxic_pool
