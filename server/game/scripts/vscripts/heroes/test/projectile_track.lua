-- game/scripts/vscripts/heroes/test/projectile_track.lua
-- 追踪投掷物测试技能: 只追踪指定目标, 命中后结算一次伤害。

local Ability = require "tinyworld.combat.ability"
local combatDamage = require "tinyworld.combat.damage"
local projectileManager = require "tinyworld.combat.projectile_manager"

ability_projectile_track = Ability.extend("ability_projectile_track")

function ability_projectile_track:OnSpellStart()
    local caster = self:GetCaster()
    local target = self:GetCursorTarget()
    if not caster or not target then return end

    self.damage = tonumber(self:GetSpecialValueFor("damage")) or 0

    projectileManager.CreateTrackingProjectile({
        Source = caster,
        Target = target,
        Ability = self,
        iMoveSpeed = tonumber(self:GetSpecialValueFor("movementSpeed")) or 40,
        range = tonumber(self:GetSpecialValueFor("range")) or 80,
        hitRadius = tonumber(self:GetSpecialValueFor("hitRadius")) or 4,
    })
end

function ability_projectile_track:OnProjectileHit(targets, x, y)
    if not self.damage or self.damage <= 0 then return end

    for _, target in ipairs(targets or {}) do
        combatDamage.dealDamage(self:GetCaster(), target, self.damage,
            combatDamage.DAMAGE_TYPE.MAGICAL, self)
    end
end

return ability_projectile_track
