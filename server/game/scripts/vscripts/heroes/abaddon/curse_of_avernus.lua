-- game/scripts/vscripts/heroes/abaddon/curse_of_avernus.lua
-- 魔霭诅咒(被动 debuff): 示例 modifier buff + debuff 的 add / remove 同步。

local abilityMod = require "tinyworld.combat.ability"
local modifierMod = require "tinyworld.combat.modifier"
local M = {}

M.ability_curse_of_avernus = abilityMod.extend("ability_curse_of_avernus")

function M.ability_curse_of_avernus:OnSpellStart()
    local target = self.target or self.caster
    target:addModifier(M.modifier_ability_curse_of_avernus_lua_debuff.new(
        self.caster, self, tonumber(self.data.slowDuration)))
    self.caster:addModifier(M.modifier_ability_curse_of_avernus_lua_buff.new(
        self.caster, self, tonumber(self.data.slowDuration)))
end

M.modifier_ability_curse_of_avernus_lua_debuff = modifierMod.extend("modifier_ability_curse_of_avernus_lua_debuff")

function M.modifier_ability_curse_of_avernus_lua_debuff:OnCreated(params)
    self.slow = tonumber(self.ability.data.attackSlow) or 20
    self.oldSpeed = self.caster:get("speed") or 6
    self.caster:set("speed", math.max(1, self.oldSpeed - self.slow * 0.06))
end

function M.modifier_ability_curse_of_avernus_lua_debuff:OnDestroy()
    if self.oldSpeed then self.caster:set("speed", self.oldSpeed) end
end

M.modifier_ability_curse_of_avernus_lua_buff = modifierMod.extend("modifier_ability_curse_of_avernus_lua_buff")

function M.modifier_ability_curse_of_avernus_lua_buff:OnCreated(params)
    self.oldSpeed = self.caster:get("speed") or 6
    self.caster:set("speed", self.oldSpeed + 1)
end

function M.modifier_ability_curse_of_avernus_lua_buff:OnDestroy()
    if self.oldSpeed then self.caster:set("speed", self.oldSpeed) end
end

return M
