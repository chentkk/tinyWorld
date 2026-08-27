-- game/components/combat_agent.lua
-- cellapp 侧战斗驱动组件: 客户端 RPC onCastAbility 释放技能。
-- 伤害 / modifier 事件由 tinyworld/combat/sync 同步给周围玩家。

local component = require "tinyworld.entity.component"
local abilityReg = require "game.scripts.vscripts.abilities"
local caster = require "tinyworld.combat.unit"
local M = {}

local CombatAgent = component.Component.extend("CombatAgent")

function CombatAgent:onCreate()
    caster.apply(self.entity)
    self:registerClientRpc("onCastAbility")
    self.abilityIndex = 0
end

function CombatAgent:onEnterCell(cell)
    local entity = self.entity
    entity.abilities = entity.abilities or {}

    if #entity.abilities == 0 then
        local ab, err = abilityReg.create(entity, "ability_aphotic_shield")
        if ab then table.insert(entity.abilities, ab) end
        ab, err = abilityReg.create(entity, "ability_borrowed_time")
        if ab then table.insert(entity.abilities, ab) end
        ab, err = abilityReg.create(entity, "ability_mist_coil")
        if ab then table.insert(entity.abilities, ab) end
    end
end

function CombatAgent:onTick(dt)
    local entity = self.entity
    if entity.combatApplied then
        entity:updateCombat(dt)
    end
end

function CombatAgent:onCastAbility(d)
    local index = tonumber(d and d.index) or 1
    -- 找一个视野内最近的“其他玩家”作为目标
    local target
    local best = math.huge
    for _, e in pairs(self.entity.cell.entities) do
        if e.id ~= self.entity.id and e.clientId and e.clientId ~= self.entity.clientId then
            local dx = e.x - self.entity.x
            local dy = e.y - self.entity.y
            local dist = dx * dx + dy * dy
            if dist < best then
                best = dist
                target = e
            end
        end
    end
    if not target then return { code = 1, msg = "no target" } end

    local ab = self.entity.abilities[index]
    if not ab then return { code = 2, msg = "no ability" } end
    if not ab:IsReady() then return { code = 3, msg = "ability not ready" } end

    -- ability 定位: 立即释放 mist_coil 用 index 3
    ab:cast(target)
    return { code = 0, msg = "cast ok" }
end

M.CombatAgent = CombatAgent
return M
