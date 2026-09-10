-- tinyworld/combat/modifier_manager.lua
-- modifier 的增删查。modifier 数据直接存放在 modifiers_view 容器中。

local Modifier = require "tinyworld.combat.modifier"

local M = {}

-- 已存在的同类 modifier 则刷新, 否则返回 nil(由调用方继续走注册流程)
local function findExisting(view, name)
    for _, old in ipairs(view:childrenList()) do
        if old:GetModifierName() == name then
            return old
        end
    end
    return nil
end

function M.addModifier(unit, mod, ability, params)
    assert(unit, "addModifier: unit required")
    assert(mod, "addModifier: mod required")
    assert(ability, "addModifier: ability required")

    local view = unit:getContainer("modifiers_view")
    assert(view, "addModifier: unit has no modifiers_view")

    -- 已存在同类 modifier: 刷新而不重复创建
    local name = type(mod) == "string" and mod or mod:GetModifierName()
    local existing = findExisting(view, name)
    if existing then
        existing:refresh({})
        unit:emit("combat_modifier_refresh", name, existing.stack)
        return existing
    end

    -- 构造步骤与迁移还原一致: newChild -> load -> add。
    -- 传入类名时由来源 ability 派生构造参数; 传入实例时直接复用该实例。
    if type(mod) == "string" then
        local spec = Modifier.buildParams(ability, params)
        spec.name = mod
        mod = view:newChild(spec)
        mod:load(spec)
    end

    mod.owner = unit
    mod:OnCreated(params or {})
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
