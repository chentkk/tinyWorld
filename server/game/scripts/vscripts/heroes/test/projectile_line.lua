-- game/scripts/vscripts/heroes/test/projectile_line.lua
-- 直线投掷物测试技能: 按施法者朝向直线前进, 途中命中所有碰撞目标。

local Ability = require "tinyworld.combat.ability"
local combatDamage = require "tinyworld.combat.damage"
local projectileManager = require "tinyworld.combat.projectile_manager"

ability_projectile_line = Ability.extend("ability_projectile_line")

function ability_projectile_line:OnSpellStart()
    local caster = self:GetCaster()
    if not caster then return end

    self.damage = tonumber(self:GetSpecialValueFor("damage")) or 0

    projectileManager.CreateLinearProjectile({
        Source = caster,
        Ability = self,
        iMoveSpeed = tonumber(self:GetSpecialValueFor("movementSpeed")) or 40,
        range = tonumber(self:GetSpecialValueFor("range")) or 80,
        hitRadius = tonumber(self:GetSpecialValueFor("hitRadius")) or 6,
        dir = caster:get("dir") or 0,
    })
end

function ability_projectile_line:OnProjectileHit(targets, x, y)
    if not self.damage or self.damage <= 0 then return end

    for _, target in ipairs(targets or {}) do
        combatDamage.dealDamage(self:GetCaster(), target, self.damage,
            combatDamage.DAMAGE_TYPE.MAGICAL, self)
    end
end

return ability_projectile_line
