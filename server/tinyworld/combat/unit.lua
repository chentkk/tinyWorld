-- tinyworld/combat/unit.lua
-- 战斗单位扩展: modifier/ability 直接存放在对应容器中。
-- 容器子对象即数据源, 字段写回自动进入 outbox 同步流程。

local M = {}

M.abilityFactory = nil

function M.setAbilityFactory(factory)
    M.abilityFactory = factory
end

function M.createAbility(caster, abilityName)
    if not M.abilityFactory then return nil, "ability factory not set" end

    local schema = nil
    if caster.getContainer then
        local view = caster:getContainer("abilities_view")
        schema = view and view.def.childSchema
    end
    return M.abilityFactory(caster, abilityName, schema)
end

-- spawn/object add 的 modifier 简述, 数据直接来自 modifiers_view
function M.modifiersSnapshot(unit)
    local out = {}
    local view = nil
    if unit.getContainer then view = unit:getContainer("modifiers_view") end
    local mods = view and view:childrenList() or {}
    for _, mod in ipairs(mods) do
        out[#out + 1] = {
            name = mod:GetModifierName(),
            duration = mod.duration,
            stack = mod.stack,
        }
    end
    return out
end

M.snapshot = M.modifiersSnapshot

function M.apply(unit)
    if unit.combatApplied then return unit end
    unit.combatApplied = true

    function unit:addModifier(mod, ability, params)
        if not mod then return nil end

        -- example 风格: 直接传 modifier 名字, 由全局 vscripts 类实例化
        if type(mod) == "string" then
            local cls = _G[mod]
            if not cls then return nil end

            local view = self:getContainer("modifiers_view")
            local schema = view and view.def.childSchema
            mod = cls.new(self, ability, params, schema)
        end

        if not mod.owner then mod.owner = self end

        local view = self:getContainer("modifiers_view")
        if not view then return nil end

        local name = mod:GetModifierName()
        for _, old in ipairs(view:childrenList()) do
            if old:GetModifierName() == name then
                old:refresh({})
                self:emit("combat_modifier_refresh", name, old.stack)
                return old
            end
        end

        mod:OnCreated(mod._params or {})
        view:add(mod)
        self:emit("combat_modifier_add", name, mod.duration, mod.stack)
        return mod
    end

    function unit:removeModifier(mod)
        local view = self:getContainer("modifiers_view")
        if not view then return nil end

        for _, old in ipairs(view:childrenList()) do
            if old == mod then
                view:remove(mod.uid)
                self:emit("combat_modifier_remove", mod:GetModifierName())
                return mod
            end
        end
        return nil
    end

    function unit:hasModifier(name)
        local view = self:getContainer("modifiers_view")
        if not view then return nil end

        for _, mod in ipairs(view:childrenList()) do
            if mod:GetModifierName() == name then return mod end
        end
        return nil
    end

    function unit:updateCombat(dt)
        local view = self:getContainer("modifiers_view")
        if view then
            for _, mod in ipairs(view:childrenList()) do
                if mod then mod:update(dt) end
            end
        end

        local abilitiesView = self:getContainer("abilities_view")
        if abilitiesView then
            for _, ab in ipairs(abilitiesView:childrenList()) do
                if ab then ab:update(dt) end
            end
        end
    end

    function unit:loadAbilities(names)
        local view = self:getContainer("abilities_view")
        if view then
            local schema = view.def.childSchema
            for _, abilityName in ipairs(names or {}) do
                local ability = M.createAbility(self, abilityName)
                if ability then
                    view:add(ability)
                end
            end
        end
        return view and view:childrenList() or {}
    end

    function unit:castAbility(index, target)
        local view = self:getContainer("abilities_view")
        local ab = view and view:childrenList()[index]
        if not ab then return false end
        return ab:cast(target)
    end

    return unit
end

return M
