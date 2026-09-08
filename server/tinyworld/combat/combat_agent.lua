-- tinyworld/combat/combat_agent.lua
-- 完整战斗组件: 能力装配/施法、状态驱动、事件转 RPC、ghost 结算入口。

local component = require "tinyworld.entity.component"
local abilityLoader = require "tinyworld.combat.ability_loader"
local combatDamage = require "tinyworld.combat.damage"
local protocol = require "tinyworld.net.protocol"

local CombatAgent = component.extend("CombatAgent")

local function reply(code, msg)
    return { code = code, msg = msg }
end

local function idOf(obj)
    if type(obj) == "table" and obj.getRealId then return obj:getRealId() end
    return obj
end

function CombatAgent:onCreate()
    local entity = self.entity

    self:registerClientRpc("onCastAbility")
    self:registerRealRpc("applyCombatDamage")
    self:registerRealRpc("applyCombatHeal")

    entity:on("combat_damage", function(_, attacker, amount, damageType, abilityName)
        self:push("onCombatDamage", {
            entityId = entity:getRealId(),
            attackerId = idOf(attacker),
            amount = amount,
            damageType = damageType,
            skill = abilityName,
        })
    end)

    entity:on("combat_heal", function(_, caster, amount, healType)
        self:push("onCombatHeal", {
            entityId = entity:getRealId(),
            casterId = idOf(caster),
            amount = amount,
            healType = healType,
        })
    end)

    entity:on("combat_cast", function(_, ability, target)
        assert(ability, "combat_cast: ability required")
        self:push("onSpellCast", {
            entityId = entity:getRealId(),
            abilityName = ability:GetAbilityName(),
            targetId = idOf(target),
        })
    end)

    assert(entity.cellInitData, "CombatAgent: entity.cellInitData required")
    assert(type(entity.cellInitData.abilities) == "table", "CombatAgent: cellInitData.abilities required")
    local names = {}
    for _, abilityName in ipairs(entity.cellInitData.abilities) do
        names[#names + 1] = abilityName
    end
    abilityLoader.loadAbilities(entity, names)
end

function CombatAgent:applyCombatDamage(data)
    data = data or {}
    return combatDamage.applyLocalDamage(self.entity, data.attackerId, data.amount,
        data.damageType, data.abilityName)
end

function CombatAgent:applyCombatHeal(data)
    data = data or {}
    return combatDamage.applyLocalHeal(self.entity, data.casterId, data.amount,
        data.healType, data.abilityName)
end

-- 框架级驱动: 也可供测试直接调用
function CombatAgent.updateCombat(unit, dt)
    local modifiersView = unit:getContainer("modifiers_view")
    if modifiersView then
        for _, mod in ipairs(modifiersView:childrenList()) do
            if mod then mod:update(dt) end
        end
    end

    local abilitiesView = unit:getContainer("abilities_view")
    if abilitiesView then
        for _, ab in ipairs(abilitiesView:childrenList()) do
            if ab then ab:update(dt) end
        end
    end
end

function CombatAgent:onTick(dt)
    CombatAgent.updateCombat(self.entity, dt)
end

function CombatAgent:resolveTarget(targetId)
    local cell = self.entity.cell
    return cell and cell:findByRealId(targetId) or nil
end

function CombatAgent:onCastAbility(d)
    d = d or {}

    local target
    local targetId = tonumber(d.targetId)
    if targetId and targetId ~= 0 then
        target = self:resolveTarget(targetId)
        if not target then return reply(1, "target not found") end
    end

    local abilitiesView = self.entity:getContainer("abilities_view")
    local ability = abilitiesView and abilitiesView:childrenList()[tonumber(d.index) or 1]
    if not ability then return reply(2, "ability not found") end
    if not ability:IsReady() then return reply(3, "ability not ready") end

    ability:cast(target)
    self.entity:emit("combat_cast", ability, target)
    return { code = 0, msg = "cast ok" }
end

-- 需要 cell 上下文, 实体进入 cell 后才可用
function CombatAgent:push(method, data)
    local entity = self.entity
    if not entity.readyForSync then return end

    local cell = entity.cell
    assert(cell, "CombatAgent:push requires entity.cell")
    cell:postEvent(entity, protocol.rpc(method, data))
end

return CombatAgent
