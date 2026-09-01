-- tinyworld/combat/unit.lua
-- 战斗单位操作函数。modifier/ability 直接存放在对应容器中,
-- 这里提供纯粹的读写/驱动函数, 不扩展 entity。

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

function M.addModifier(unit, mod, ability, params)
    if not mod then return nil end

    if type(mod) == "string" then
        local cls = _G[mod]
        if not cls then return nil end

        local view = unit:getContainer("modifiers_view")
        local schema = view and view.def.childSchema
        mod = cls.new(unit, ability, params, schema)
    end

    if not mod.owner then mod.owner = unit end

    local view = unit:getContainer("modifiers_view")
    if not view then return nil end

    local name = mod:GetModifierName()
    for _, old in ipairs(view:childrenList()) do
        if old:GetModifierName() == name then
            old:refresh({})
            unit:emit("combat_modifier_refresh", name, old.stack)
            return old
        end
    end

    mod:OnCreated(mod._params or {})
    view:add(mod)
    unit:emit("combat_modifier_add", name, mod.duration, mod.stack)
    return mod
end

function M.removeModifier(unit, mod)
    local view = unit:getContainer("modifiers_view")
    if not view then return nil end

    for _, old in ipairs(view:childrenList()) do
        if old == mod then
            view:remove(mod.uid)
            unit:emit("combat_modifier_remove", mod:GetModifierName())
            return mod
        end
    end
    return nil
end

function M.hasModifier(unit, name)
    local view = unit:getContainer("modifiers_view")
    if not view then return nil end

    for _, mod in ipairs(view:childrenList()) do
        if mod:GetModifierName() == name then return mod end
    end
    return nil
end

function M.updateCombat(unit, dt)
    local view = unit:getContainer("modifiers_view")
    if view then
        for _, mod in ipairs(view:childrenList()) do
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

function M.loadAbilities(unit, names)
    local view = unit:getContainer("abilities_view")
    if view then
        for _, abilityName in ipairs(names or {}) do
            local ability = M.createAbility(unit, abilityName)
            if ability then view:add(ability) end
        end
    end
    return view and view:childrenList() or {}
end

function M.castAbility(unit, index, target)
    local view = unit:getContainer("abilities_view")
    local ab = view and view:childrenList()[index]
    if not ab then return false end
    return ab:cast(target)
end

return M
