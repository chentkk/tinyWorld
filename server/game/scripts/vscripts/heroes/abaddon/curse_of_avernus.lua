-- game/scripts/vscripts/heroes/abaddon/curse_of_avernus.lua
-- 魔霭诅咒: 被动 via GetIntrinsicModifierName, 攻击落地事件叠加 debuff/buff。

local Ability = require "tinyworld.combat.ability"
local combatUnit = require "tinyworld.combat.unit"
local Modifier = require "tinyworld.combat.modifier"

ability_curse_of_avernus = Ability.extend("ability_curse_of_avernus")
modifier_ability_curse_of_avernus_lua = Modifier.extend("modifier_ability_curse_of_avernus_lua")
modifier_ability_curse_of_avernus_lua_debuff = Modifier.extend("modifier_ability_curse_of_avernus_lua_debuff")
modifier_ability_curse_of_avernus_lua_buff = Modifier.extend("modifier_ability_curse_of_avernus_lua_buff")

function ability_curse_of_avernus:GetIntrinsicModifierName()
    return "modifier_ability_curse_of_avernus_lua"
end

modifier_ability_curse_of_avernus_lua.IsHidden = function(self) return true end
modifier_ability_curse_of_avernus_lua.IsPurgable = function(self) return false end
modifier_ability_curse_of_avernus_lua.IsBuff = function(self) return true end

function modifier_ability_curse_of_avernus_lua:OnCreated(data)
    self.parent = self:GetParent()
end

function modifier_ability_curse_of_avernus_lua:OnAttackLanded(data)
    if not data or not data.target then return end
    if data.attacker ~= self.parent then return end
    if combatUnit.hasModifier(data.target, "modifier_ability_curse_of_avernus_lua_debuff") then return end

    local ability = self:GetAbility()
    data.combatUnit.addModifier(target, "modifier_ability_curse_of_avernus_lua_debuff", ability, {
        duration = tonumber(ability.data.slowDuration) or 2,
    })
    combatUnit.addModifier(self:GetCaster(), "modifier_ability_curse_of_avernus_lua_buff", ability, {
        duration = tonumber(ability.data.slowDuration) or 2,
    })
end

function modifier_ability_curse_of_avernus_lua_debuff:OnCreated(data)
    self.parent = self:GetParent()
    self.slow = tonumber(self:GetAbility().data.attackSlow) or 20
    self.oldSpeed = self:GetParent():get("speed") or 6
    self:GetParent():set("speed", math.max(1, self.oldSpeed - self.slow * 0.06))
end

function modifier_ability_curse_of_avernus_lua_debuff:OnDestroy()
    if self.oldSpeed then self:GetParent():set("speed", self.oldSpeed) end
end

function modifier_ability_curse_of_avernus_lua_buff:OnCreated(data)
    self.parent = self:GetParent()
    self.oldSpeed = self:GetParent():get("speed") or 6
    self:GetParent():set("speed", self.oldSpeed + 1)
end

function modifier_ability_curse_of_avernus_lua_buff:OnDestroy()
    if self.oldSpeed then self:GetParent():set("speed", self.oldSpeed) end
end
