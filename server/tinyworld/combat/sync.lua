-- tinyworld/combat/sync.lua
-- 战斗同步组件(cellapp 侧底层同步层)。
-- 监听 combat_damage / combat_heal 一次性事件转成客户端 RPC。
-- modifier 状态由 modifiers_view 同步, 不在这里重复下发。
-- 战斗核心与技能脚本不碰网络, 底层通信全部收敛在本组件。

local component = require "tinyworld.entity.component"

local CombatSync = component.extend("CombatSync")

function CombatSync:onCreate()
    local entity = self.entity

    entity:on("combat_damage", function(_, attacker, amount, damageType, abilityName)
        self:push("onCombatDamage", {
            entityId = entity.clientId,
            attackerId = attacker and attacker.clientId,
            amount = amount,
            damageType = damageType,
            skill = abilityName,
        })
    end)

    entity:on("combat_heal", function(_, caster, amount, healType)
        self:push("onCombatHeal", {
            entityId = entity.clientId,
            casterId = caster and caster.clientId,
            amount = amount,
            healType = healType,
        })
    end)

    entity:on("combat_cast", function(_, ability, target)
        self:push("onSpellCast", {
            entityId = entity.clientId,
            abilityName = ability and ability:GetAbilityName(),
            targetId = target and (target.clientId or target.id),
        })
    end)

    -- modifier 状态统一由 modifiers_view 同步, 不再发一次性 RPC
end

-- 需要 cell 上下文, 实体进入 cell 后才可用
function CombatSync:push(method, data)
    local entity = self.entity
    if not entity.readyForSync then return end

    local cell = entity.cell
    if not cell then return end

    -- cell 负责排队与冲刷, sync 不直接访问 cell 内部结构
    cell:postEvent(entity, { t = "RPC", n = method, d = data })
end

return CombatSync
