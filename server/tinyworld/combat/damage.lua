-- tinyworld/combat/damage.lua
-- 伤害 / 治疗结算。数值最终落到实体属性(hp / mp)上,
-- 由层的属性同步系统下发到客户端。战斗系统只负责计算与发事件,
-- 不直接发送任何网络消息, 客户端与服务器共用同一份代码。

local M = {}

M.DAMAGE_TYPE = {
    PHYSICAL = 1,
    MAGICAL = 2,
    PURE = 3,
}

M.HEAL_TYPE = {
    HEAL = 1,
    REGEN = 2,
}

local function attackerOrCasterId(unit)
    if unit == nil then return nil end
    if type(unit) == "table" and unit.getRealId then return unit:getRealId() end
    return unit
end

-- 本地按 id 结算(real 所在 app 内执行)
function M.applyLocalDamage(target, attackerId, amount, damageType, abilityName)
    amount = math.floor(amount or 0)
    damageType = damageType or M.DAMAGE_TYPE.PHYSICAL
    if amount <= 0 then return 0 end

    local incomingData = {
        attacker = attackerId,
        damage = amount,
        damage_type = damageType,
        ability = abilityName,
    }
    local modifiersView = target.getContainer and target:getContainer("modifiers_view")
    for _, mod in ipairs(modifiersView and modifiersView:childrenList() or {}) do
        if mod.GetModifierIncomingDamage_Percentage then
            local pct = mod:GetModifierIncomingDamage_Percentage(incomingData) or 0
            amount = amount * (1 + pct / 100)
        end
    end
    amount = math.floor(amount)
    if amount <= 0 then return 0 end

    local hp = target:get("hp") or 0
    target:set("hp", math.max(0, hp - amount))
    target:emit("combat_damage", attackerId, amount, damageType, abilityName)
    return amount
end

function M.applyLocalHeal(target, casterId, amount, healType, abilityName)
    amount = math.floor(amount or 0)
    healType = healType or M.HEAL_TYPE.HEAL
    if amount <= 0 then return 0 end

    local hp = target:get("hp") or 0
    local maxHp = target:get("maxHp") or hp
    target:set("hp", math.min(maxHp, hp + amount))
    target:emit("combat_heal", casterId, amount, healType, abilityName)
    return amount
end

function M.dealDamage(attacker, target, amount, damageType, sourceAbility)
    amount = math.floor(amount or 0)
    damageType = damageType or M.DAMAGE_TYPE.PHYSICAL
    if amount <= 0 or not target or not target.def then return 0 end

    local abilityName = sourceAbility and sourceAbility:GetAbilityName() or nil

    -- ghost 目标: 路由到 real 所在 app 结算
    if target.isGhost and target.callReal then
        return target:callReal("applyCombatDamage", {
            attackerId = attackerOrCasterId(attacker),
            amount = amount,
            damageType = damageType,
            abilityName = abilityName,
        })
    end

    if amount < 0 then
        return dealHealId(attacker, target, -amount, M.HEAL_TYPE.REGEN, abilityName)
    end

    return M.applyLocalDamage(target, attackerOrCasterId(attacker), amount, damageType, abilityName)
end

function M.dealHeal(caster, target, amount, healType, sourceAbility)
    amount = math.floor(amount or 0)
    healType = healType or M.HEAL_TYPE.HEAL
    if amount <= 0 or not target or not target.def then return 0 end

    local abilityName = sourceAbility and sourceAbility:GetAbilityName() or nil

    if target.isGhost and target.callReal then
        return target:callReal("applyCombatHeal", {
            casterId = attackerOrCasterId(caster),
            amount = amount,
            healType = healType,
            abilityName = abilityName,
        })
    end

    return M.applyLocalHeal(target, attackerOrCasterId(caster), amount, healType, abilityName)
end

function dealHealId(caster, target, amount, healType, abilityName)
    return M.dealHeal(caster, target, amount, healType, abilityName)
end

return M
