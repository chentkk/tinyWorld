-- game/scripts/vscripts/heroes/abaddon/curse_of_avernus.lua
-- 魔霭诅咒(被动 debuff 示例)。

local Ability = require "tinyworld.combat.ability"
local Modifier = require "tinyworld.combat.modifier"

ability_curse_of_avernus = Ability.extend("ability_curse_of_avernus")
modifier_ability_curse_of_avernus_lua_debuff = Modifier.extend("modifier_ability_curse_of_avernus_lua_debuff")
modifier_ability_curse_of_avernus_lua_buff = Modifier.extend("modifier_ability_curse_of_avernus_lua_buff")

function ability_curse_of_avernus:OnSpellStart()
    local target = self.target or self.caster
    target:addModifier(modifier_ability_curse_of_avernus_lua_debuff.new(
        self.caster, self, tonumber(self.data.slowDuration)))
    self.caster:addModifier(modifier_ability_curse_of_avernus_lua_buff.new(
        self.caster, self, tonumber(self.data.slowDuration)))
end

function modifier_ability_curse_of_avernus_lua_debuff:OnCreated(params)
    self.slow = tonumber(self.ability.data.attackSlow) or 20
    self.oldSpeed = self.caster:get("speed") or 6
    self.caster:set("speed", math.max(1, self.oldSpeed - self.slow * 0.06))
end

function modifier_ability_curse_of_avernus_lua_debuff:OnDestroy()
    if self.oldSpeed then self.caster:set("speed", self.oldSpeed) end
end

function modifier_ability_curse_of_avernus_lua_buff:OnCreated(params)
    self.oldSpeed = self.caster:get("speed") or 6
    self.caster:set("speed", self.oldSpeed + 1)
end

function modifier_ability_curse_of_avernus_lua_buff:OnDestroy()
    if self.oldSpeed then self.caster:set("speed", self.oldSpeed) end
end

