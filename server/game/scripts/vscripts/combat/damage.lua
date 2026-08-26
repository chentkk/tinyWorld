-- game/scripts/vscripts/combat/damage.lua
-- 伤害类型与伤害结算。造成伤害后, 数值通过实体属性(hp)自动同步客户端,
-- 底层通信(属性同步)负责下发, 战斗系统不直接处理网络。

local M = {}

M.DAMAGE_TYPE = {
    PHYSICAL = 1,
    MAGICAL = 2,
    PURE = 3,
}

function M.dealDamage(attacker, target, amount, damageType)
    amount = math.floor(amount or 0)
    damageType = damageType or M.DAMAGE_TYPE.PHYSICAL
    if amount <= 0 then return 0 end
    if not target or not target.def then return 0 end

    local hp = target:get("hp") or 0
    target:set("hp", math.max(0, hp - amount))
    target:emit("on_damage", attacker, amount, damageType)
    return amount
end

return M
