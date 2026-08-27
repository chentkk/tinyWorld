-- tinyworld/combat/sync.lua
-- 战斗同步组件(cellapp 侧底层同步层)。
-- 监听实体发出的 combat_damage / combat_heal / combat_modifier_* 一次性事件,
-- 把这些事件转换成客户端 RPC, 下发给自己以及周围所有玩家。
-- 战斗核心与技能脚本不碰网络, 底层通信全部收敛在本组件。

local component = require "tinyworld.entity.component"
local M = {}

local CombatSync = component.Component.extend("CombatSync")

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

    entity:on("combat_modifier_add", function(_, name, duration, stack)
        self:push("onModifierAdd", {
            entityId = entity.clientId, modifier = name, duration = duration, stack = stack })
    end)

    entity:on("combat_modifier_remove", function(_, name)
        self:push("onModifierRemove", { entityId = entity.clientId, modifier = name })
    end)

    entity:on("combat_modifier_refresh", function(_, name, stack)
        self:push("onModifierRefresh", { entityId = entity.clientId, modifier = name, stack = stack })
    end)
end

-- 需要 cell 上下文, 实体进入 cell 后才可用
function CombatSync:push(method, data)
    local entity = self.entity
    local cell = entity.cell
    if not cell or not cell.app then return end

    local msg = { t = "RPC", n = method, d = data }

    -- 自己: 血量等属性同步之外, 还需要播放伤害数字
    if entity.kind == "Player" then
        cell.app:sendToClient(entity, msg)
    end
    -- 周围所有玩家
    cell:sendToAround(entity, msg)
end

M.CombatSync = CombatSync
return M
