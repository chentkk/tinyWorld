-- game/scripts/vscripts/heroes/test/projectile_line.lua
-- 直线投掷物测试技能: 按施法者朝向直线前进, 途中对所有碰撞目标造成伤害。
-- 伤害通过 CreateLinearProjectile 的内置 damage option 表达式, 不再写 onHit 循环。

local Ability = require "tinyworld.combat.ability"
local combatDamage = require "tinyworld.combat.damage"
local projectileManager = require "tinyworld.combat.projectile_manager"

ability_projectile_line = Ability.extend("ability_projectile_line")

function ability_projectile_line:OnSpellStart()
    local caster = self:GetCaster()
    if not caster then return end

    projectileManager.CreateLinearProjectile({
        Source = caster,
        Ability = self,
        iMoveSpeed = tonumber(self:GetSpecialValueFor("movementSpeed")) or 400,
        range = tonumber(self:GetSpecialValueFor("range")) or 80,
        hitRadius = tonumber(self:GetSpecialValueFor("hitRadius")) or 6,
        angle = caster:get("dir") or 0,
        damage = {
            amount = tonumber(self:GetSpecialValueFor("damage")) or 0,
            type = combatDamage.DAMAGE_TYPE.MAGICAL,
        },
    })
end

return ability_projectile_line
