-- tinyworld/app/cellapp/settlement.lua
-- 战斗结算组件: 挂在 real 实体上, 注册 ghost -> real 的结算 RPC。
-- 伤害/治疗仍在 combat.damage 内结算, 本组件只负责 RPC 入口。

local component = require "tinyworld.entity.component"
local combatDamage = require "tinyworld.combat.damage"

local CombatSettlement = component.extend("CombatSettlement")

function CombatSettlement:onCreate()
    self:registerRealRpc("applyCombatDamage")
    self:registerRealRpc("applyCombatHeal")
end

function CombatSettlement:applyCombatDamage(data)
    data = data or {}
    return combatDamage.applyLocalDamage(self.entity, data.attackerId, data.amount,
        data.damageType, data.abilityName)
end

function CombatSettlement:applyCombatHeal(data)
    data = data or {}
    return combatDamage.applyLocalHeal(self.entity, data.casterId, data.amount,
        data.healType, data.abilityName)
end

return CombatSettlement
