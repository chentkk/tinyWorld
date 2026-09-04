-- game/scripts/vscripts/heroes/test/projectile_track.lua
-- 追踪投掷物测试技能: 追踪指定目标, 命中后结算一次伤害。
-- 命中后销毁由 CreateTrackingProjectile 的 homing 语义处理。

local Ability = require "tinyworld.combat.ability"
local combatDamage = require "tinyworld.combat.damage"
local projectileManager = require "tinyworld.combat.projectile_manager"

ability_projectile_track = Ability.extend("ability_projectile_track")

function ability_projectile_track:OnSpellStart()
    local caster = self:GetCaster()
    local target = self:GetCursorTarget()
    if not caster or not target then return end

    projectileManager.CreateTrackingProjectile({
        Source = caster,
        Target = target,
        Ability = self,
        iMoveSpeed = tonumber(self:GetSpecialValueFor("movementSpeed")) or 40,
        range = tonumber(self:GetSpecialValueFor("range")) or 80,
        hitRadius = tonumber(self:GetSpecialValueFor("hitRadius")) or 4,
        damage = {
            amount = tonumber(self:GetSpecialValueFor("damage")) or 0,
            type = combatDamage.DAMAGE_TYPE.MAGICAL,
        },
    })
end

return ability_projectile_track
