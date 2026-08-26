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

function M.dealDamage(attacker, target, amount, damageType)
    amount = math.floor(amount or 0)
    damageType = damageType or M.DAMAGE_TYPE.PHYSICAL
    if amount <= 0 or not target or not target.def then return 0 end

    -- modifier 钩子: 护盾 / 免伤 / 伤害转治疗等统一在 modifier 层处理
    for _, mod in ipairs(target.modifiers or {}) do
        if mod.OnDamageReceived then
            amount = mod:OnDamageReceived(attacker, amount, damageType) or 0
        end
    end
    if amount == 0 then return 0 end

    local hp = target:get("hp") or 0
    if amount < 0 then
        -- 负伤害 = 治疗(如回光返照)
        return M.dealHeal(attacker, target, -amount, M.HEAL_TYPE.REGEN)
    end

    target:set("hp", math.max(0, hp - amount))
    target:emit("combat_damage", attacker, amount, damageType)
    if attacker then
        attacker:emit("combat_damage_dealt", target, amount, damageType)
    end
    return amount
end

function M.dealHeal(caster, target, amount, healType)
    amount = math.floor(amount or 0)
    healType = healType or M.HEAL_TYPE.HEAL
    if amount <= 0 or not target or not target.def then return 0 end

    local hp = target:get("hp") or 0
    local maxHp = target:get("maxHp") or hp
    target:set("hp", math.min(maxHp, hp + amount))
    target:emit("combat_heal", caster, amount, healType)
    return amount
end

return M
