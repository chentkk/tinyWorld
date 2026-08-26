-- game/scripts/vscripts/combat/caster.lua
-- 战斗单位扩展: 挂 modifier、驱动 ability 的 update 帧。

local env = require "game.scripts.vscripts.combat.env"
local M = {}

function M.apply(unit)
    if unit.combatModifiers then return unit end

    unit.combatModifiers = {}
    unit.abilities = unit.abilities or {}

    function unit:addModifier(mod)
        local list = self.combatModifiers
        for i, old in ipairs(list) do
            if old:GetModifierName() == mod:GetModifierName() then
                old:OnRefresh(mod and {})
                return old
            end
        end
        list[#list + 1] = mod
        mod:OnCreated({})
        return mod
    end

    function unit:removeModifier(mod)
        for i, old in ipairs(self.combatModifiers) do
            if old == mod then
                table.remove(self.combatModifiers, i)
                return
            end
        end
    end

    function unit:updateCombat(dt)
        for _, mod in ipairs(self.combatModifiers) do
            mod:update(dt)
        end
        for _, ab in ipairs(self.abilities) do
            ab:update(dt)
        end
    end

    function unit:castAbility(index, target)
        local ab = self.abilities[index]
        if not ab then return false end
        return ab:cast(target)
    end

    return unit
end

M.env = env
return M
