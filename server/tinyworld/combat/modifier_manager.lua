-- tinyworld/combat/modifier_manager.lua
-- modifier 的增删查。modifier 数据直接存放在 modifiers_view 容器中。

local M = {}

function M.addModifier(unit, mod, ability, params)
    assert(unit, "addModifier: unit required")
    assert(mod, "addModifier: mod required")
    assert(ability, "addModifier: ability required")

    if type(mod) == "string" then
        local cls = assert(_G[mod], "addModifier: unknown modifier class " .. tostring(mod))
        local view = unit:getContainer("modifiers_view")
        assert(view, "addModifier: unit has no modifiers_view")
        mod = cls.new(unit, ability, params, view.def.childSchema)
    end

    if not mod.owner then mod.owner = unit end

    local view = unit:getContainer("modifiers_view")
    assert(view, "addModifier: unit has no modifiers_view")

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
    assert(view, "removeModifier: unit has no modifiers_view")

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
    assert(view, "hasModifier: unit has no modifiers_view")

    for _, mod in ipairs(view:childrenList()) do
        if mod:GetModifierName() == name then return mod end
    end
    return nil
end

return M
