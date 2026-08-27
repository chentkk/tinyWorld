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

function M.dealDamage(attacker, target, amount, damageType, sourceAbility)
    amount = math.floor(amount or 0)
    damageType = damageType or M.DAMAGE_TYPE.PHYSICAL
    if amount <= 0 or not target or not target.def then return 0 end

    -- modifier 钩子: 对齐 example 的 GetModifierIncomingDamage_Percentage(data)
    local incomingData = {
        attacker = attacker,
        damage = amount,
        damage_type = damageType,
        ability = sourceAbility,
    }
    for _, mod in ipairs(target.modifiers or {}) do
        if mod.GetModifierIncomingDamage_Percentage then
            local pct = mod:GetModifierIncomingDamage_Percentage(incomingData) or 0
            amount = amount * (1 + pct / 100)
        end
    end
    amount = math.floor(amount)
    if amount <= 0 then return 0 end

    local hp = target:get("hp") or 0
    if amount < 0 then
        -- 负伤害 = 治疗(如回光返照)
        return M.dealHeal(attacker, target, -amount, M.HEAL_TYPE.REGEN, sourceAbility)
    end

    local abilityName = sourceAbility and sourceAbility._name or nil
    target:set("hp", math.max(0, hp - amount))
    target:emit("combat_damage", attacker, amount, damageType, abilityName)
    if attacker then
        attacker:emit("combat_damage_dealt", target, amount, damageType, abilityName)
    end
    return amount
end

function M.dealHeal(caster, target, amount, healType, sourceAbility)
    amount = math.floor(amount or 0)
    healType = healType or M.HEAL_TYPE.HEAL
    if amount <= 0 or not target or not target.def then return 0 end

    local hp = target:get("hp") or 0
    local maxHp = target:get("maxHp") or hp
    target:set("hp", math.min(maxHp, hp + amount))
    local abilityName = sourceAbility and sourceAbility._name or nil
    target:emit("combat_heal", caster, amount, healType, abilityName)
    return amount
end

return M
