-- game/scripts/vscripts/heroes/abaddon/borrowed_time.lua
-- 回光返照: 被动 modifier 在低血量时自动开启持续施法。

local Ability = require "tinyworld.combat.ability"
local Modifier = require "tinyworld.combat.modifier"

ability_borrowed_time = Ability.extend("ability_borrowed_time")
modifier_ability_borrowed_time_passive = Modifier.extend("modifier_ability_borrowed_time_passive")
modifier_abaddon_borrowed_time_lua_active = Modifier.extend("modifier_abaddon_borrowed_time_lua_active")

function ability_borrowed_time:GetIntrinsicModifierName()
    return "modifier_ability_borrowed_time_passive"
end

function ability_borrowed_time:OnChannelStart()
    self.caster:addModifier("modifier_abaddon_borrowed_time_lua_active", self, {
        duration = tonumber(self.data.duration),
    })
end

function ability_borrowed_time:OnChannelFinish()
    local active = self.caster:hasModifier("modifier_abaddon_borrowed_time_lua_active")
    if active then active:destroy() end
end

function ability_borrowed_time:startCooldown()
    Ability.startCooldown(self)
end

function modifier_ability_borrowed_time_passive:OnIntervalThink()
    local caster = self.caster
    local hp = caster:get("hp") or 0
    local maxHp = caster:get("maxHp") or 1
    local pct = tonumber(self.ability.data.threshold_pct) or 30

    if hp / maxHp * 100 < pct and self.ability:IsReady() then
        self.ability:cast(caster)
    end
end

function modifier_abaddon_borrowed_time_lua_active:GetModifierIncomingDamage_Percentage(data)
    return -100 -- 回光返照期间受伤害转为 0, 实际治疗由业务结算
end

