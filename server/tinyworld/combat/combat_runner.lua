-- tinyworld/combat/combat_runner.lua
-- 每帧驱动 modifier / ability 更新。

local M = {}

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

return M
