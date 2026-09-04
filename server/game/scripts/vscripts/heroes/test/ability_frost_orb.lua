-- game/scripts/vscripts/heroes/test/ability_frost_orb.lua
-- 示例: 冰封宝珠。
-- 在目标点制造一个持续 5 秒、每 0.5 秒对 40 范围内敌人造成伤害并附加减速的宝珠。
-- 使用统一 projectileManager.Create: movement="none" 表示静止;
-- 周期行为用 onIntervalThink; 框架自动处理实体生命周期与同步。

local Ability = require "tinyworld.combat.ability"
local combatDamage = require "tinyworld.combat.damage"
local modifierManager = require "tinyworld.combat.modifier_manager"
local projectileManager = require "tinyworld.combat.projectile_manager"

ability_frost_orb = Ability.extend("ability_frost_orb")

function ability_frost_orb:OnSpellStart()
    local caster = self:GetCaster()
    if not caster then return end

    -- 目标点: 这里示例直接往 caster 前方 60 放; 实际业务可替换成瞄准点
    local dx = math.cos(caster:get("dir") or 0)
    local dy = math.sin(caster:get("dir") or 0)
    local x = caster.x + dx * 60
    local y = caster.y + dy * 60

    projectileManager.Create({
        Source = caster,
        Ability = self,
        movement = "none",
        x = x, y = y,
        duration = tonumber(self:GetSpecialValueFor("duration")) or 5,
        tickInterval = tonumber(self:GetSpecialValueFor("tickInterval")) or 0.5,
        areaRadius = tonumber(self:GetSpecialValueFor("areaRadius")) or 40,

        -- 内置周期伤害: 框架在 onIntervalThink 前自动执行
        tickDamage = {
            amount = tonumber(self:GetSpecialValueFor("damage")) or 12,
            type = combatDamage.DAMAGE_TYPE.MAGICAL,
        },

        -- 使用层附加效果: 范围减速
        onIntervalThink = function(projectile, targets, tickIndex)
            for _, target in ipairs(targets) do
                modifierManager.addModifier(target, "modifier_frost_slow", self, { duration = 1.5 })
            end
        end,
    })
end

return ability_frost_orb
