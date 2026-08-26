-- game/scripts/vscripts/heroes/abaddon/borrowed_time.lua
-- 回光返照: 被动 modifier 在低血量时自动开启持续施法。
-- 施法期间对应的 active modifier 把受到的伤害转化为治疗。

local abilityMod = require "tinyworld.combat.ability"
local modifierMod = require "tinyworld.combat.modifier"
local M = {}

M.ability_borrowed_time = abilityMod.Ability.extend("ability_borrowed_time")

function M.ability_borrowed_time:onCreateAbility()
    self.caster:addModifier(M.modifier_ability_borrowed_time_passive.new(self.caster, self, nil))
end

function M.ability_borrowed_time:OnChannelStart()
    self.caster:addModifier(M.modifier_abaddon_borrowed_time_lua_active.new(
        self.caster, self, tonumber(self.data.duration)))
end

function M.ability_borrowed_time:OnChannelFinish()
    local active = self.caster:hasModifier("modifier_abaddon_borrowed_time_lua_active")
    if active then active:destroy() end
end

-- 冷却结束后重置, 便于被动再次触发
function M.ability_borrowed_time:startCooldown()
    abilityMod.Ability.startCooldown(self)
end

M.modifier_ability_borrowed_time_passive = modifierMod.Modifier.extend("modifier_ability_borrowed_time_passive")

function M.modifier_ability_borrowed_time_passive:OnIntervalThink()
    local caster = self.caster
    local hp = caster:get("hp") or 0
    local maxHp = caster:get("maxHp") or 1
    local pct = tonumber(self.ability.data.threshold_pct) or 30

    if hp / maxHp * 100 < pct and self.ability:IsReady() then
        self.ability:cast(caster)
    end
end

M.modifier_abaddon_borrowed_time_lua_active = modifierMod.Modifier.extend("modifier_abaddon_borrowed_time_lua_active")

function M.modifier_abaddon_borrowed_time_lua_active:OnDamageReceived(attacker, amount, damageType)
    return -amount -- 转化为治疗
end

return M
