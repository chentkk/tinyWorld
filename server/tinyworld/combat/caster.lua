-- tinyworld/combat/caster.lua
-- 战斗单位扩展: 管理 modifier 与 ability, 驱动每帧 update。
-- modifier 的增删刷通过事件(combat_modifier_add/remove/refresh)通知,
-- 由上层同步(如 buff view)决定如何下发, 战斗核心不碰网络。

local M = {}

function M.apply(unit)
    if unit.combatApplied then return unit end
    unit.combatApplied = true

    unit.modifiers = unit.modifiers or {}
    unit.abilities = unit.abilities or {}

    function unit:addModifier(mod)
        if not mod then return nil end
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
        mod:OnCreated({})
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

    function unit:castAbility(index, target)
        local ab = self.abilities[index]
        if not ab then return false end
        return ab:cast(target)
    end

    return unit
end

return M
