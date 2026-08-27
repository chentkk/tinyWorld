-- tinyworld/combat/unit.lua
-- 战斗单位扩展: 管理 modifier 与 ability, 驱动每帧 update。
-- modifier 的增删刷通过事件(combat_modifier_add/remove/refresh)通知,
-- 由上层同步(如 buff view)决定如何下发, 战斗核心不碰网络。

local M = {}

-- 能力工厂: 项目启动时由 game.scripts.vscripts.abilities 注册。
-- 能力创建由 unit/entity 层统一处理, 业务组件无需知道 npc / vscripts 路径。
M.abilityFactory = nil

function M.setAbilityFactory(factory)
    M.abilityFactory = factory
end

function M.createAbility(caster, abilityName)
    if not M.abilityFactory then return nil, "ability factory not set" end
    return M.abilityFactory(caster, abilityName)
end

function M.modifiersSnapshot(unit)
    local out = {}
    for _, mod in ipairs(unit.modifiers or {}) do
        out[#out + 1] = {
            name = mod:GetModifierName(),
            duration = mod.duration,
            stack = mod.stack,
        }
    end
    return out
end

M.snapshot = M.modifiersSnapshot

local function round2(n)
    n = tonumber(n) or 0
    return math.floor(n * 100 + 0.5) / 100
end

-- 把 modifier / ability 状态同步到通用 View(只写有变化的值, 减少 ops)
function M.syncCombatViews(unit, dt)
    if not unit.getContainer then return end

    local modifiersView = unit:getContainer("modifiers_view")
    if modifiersView and modifiersView:isViewOpened() then
        local seen = {}
        for _, mod in ipairs(unit.modifiers or {}) do
            local id = mod.uid
            local remaining = mod.duration and math.max(0, mod.duration - mod.elapsed) or 0
            if not modifiersView:has(id) then
                modifiersView:add({ id = id, name = mod:GetModifierName(),
                    stack = mod.stack, duration = round2(mod.duration), remaining = round2(remaining) })
            else
                modifiersView:setChildProp(id, "stack", mod.stack)
                modifiersView:setChildProp(id, "remaining", round2(remaining))
            end
            seen[id] = true
        end
        for id in pairs(modifiersView.children) do
            if not seen[id] then modifiersView:remove(id) end
        end
    end

    local abilitiesView = unit:getContainer("abilities_view")
    if abilitiesView and abilitiesView:isViewOpened() then
        for _, ability in ipairs(unit.abilities or {}) do
            local id = ability:GetAbilityName()
            if id and not abilitiesView:has(id) then
                abilitiesView:add({ id = id, level = ability.level or 1,
                    cooldownLeft = round2(ability.cooldownLeft or 0), state = ability.state or "ready" })
            else
                abilitiesView:setChildProp(id, "cooldownLeft", round2(ability.cooldownLeft))
                abilitiesView:setChildProp(id, "state", ability.state)
            end
        end
    end
end

function M.apply(unit)
    if unit.combatApplied then return unit end
    unit.combatApplied = true

    unit.modifiers = unit.modifiers or {}
    unit.abilities = unit.abilities or {}

    function unit:addModifier(mod, ability, params)
        if not mod then return nil end

        -- example 风格: 直接传 modifier 名字, 由全局 vscripts 类实例化
        if type(mod) == "string" then
            local cls = _G[mod]
            if not cls then return nil end
            mod = cls.new(self, ability, params)
        end

        if not mod.owner then mod.owner = self end

        local name = mod:GetModifierName()
        for _, old in ipairs(self.modifiers) do
            if old:GetModifierName() == name then
                old:refresh({})
                self:emit("combat_modifier_refresh", name, old.stack)
                return old
            end
        end

        self.modifiers[#self.modifiers + 1] = mod
        mod:OnCreated(mod._params or {})
        self:emit("combat_modifier_add", name, mod.duration, mod.stack)
        return mod
    end

    function unit:removeModifier(mod)
        for i, old in ipairs(self.modifiers) do
            if old == mod then
                table.remove(self.modifiers, i)
                self:emit("combat_modifier_remove", mod:GetModifierName())
                return mod
            end
        end
        return nil
    end

    function unit:hasModifier(name)
        for _, mod in ipairs(self.modifiers) do
            if mod:GetModifierName() == name then return mod end
        end
        return nil
    end

    function unit:updateCombat(dt)
        for i, mod in ipairs(self.modifiers) do
            if mod then mod:update(dt) end
        end
        for i, ab in ipairs(self.abilities) do
            if ab then ab:update(dt) end
        end
    end

    function unit:loadAbilities(names)
        self.abilities = {}
        for _, abilityName in ipairs(names or {}) do
            local ability = M.createAbility(self, abilityName)
            if ability then
                self.abilities[#self.abilities + 1] = ability
            end
        end
        return self.abilities
    end

    function unit:castAbility(index, target)
        local ab = self.abilities[index]
        if not ab then return false end
        return ab:cast(target)
    end

    return unit
end

return M
