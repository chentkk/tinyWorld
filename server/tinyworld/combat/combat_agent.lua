-- tinyworld/combat/combat_agent.lua
-- cellapp 侧战斗驱动组件。
-- 技能属于玩家数据: baseapp 加载后经 cellInitData 传入, 组件只负责装配与施放。
-- 客户端请求释放技能时携带目标 targetId 与技能 index。

local component = require "tinyworld.entity.component"
local abilityLoader = require "tinyworld.combat.ability_loader"

local CombatAgent = component.extend("CombatAgent")

local function reply(code, msg)
    return { code = code, msg = msg }
end

function CombatAgent:onCreate()
    self:registerClientRpc("onCastAbility")

    local names = {}
    for _, abilityName in ipairs(self.entity.cellInitData and self.entity.cellInitData.abilities or {}) do
        names[#names + 1] = abilityName
    end
    abilityLoader.loadAbilities(self.entity, names)
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
    local cellEntities = self.entity.cell and self.entity.cell.entities or {}
    for _, candidate in pairs(cellEntities) do
        if candidate:getRealId() == targetId then return candidate end
    end
    return nil
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

return CombatAgent
