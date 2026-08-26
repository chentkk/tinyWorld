-- client/src/ui.lua
-- 背包 / 装备栏界面(基于通用视图客户端) + cell 网格开关按钮。

local views = require "src.views"
local M = {}

M.panelsOpen = { bag = true, equipment = true }
M.showGrid = true

local buttons = {
    { label = "grid",       x = 10, y = 10, w = 90, h = 26, key = "grid" },
    { label = "bag",        x = 10, y = 44, w = 90, h = 26, key = "bag" },
    { label = "equipment",  x = 10, y = 78, w = 90, h = 26, key = "equipment" },
}

function M.toggleKey(key)
    if key == "grid" then
        M.showGrid = not M.showGrid
    else
        M.panelsOpen[key] = not M.panelsOpen[key]
    end
end

local function drawPanel(title, children, cols, x, y, w, h)
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(title, x + 8, y + 6)

    local i = 0
    for id, data in pairs(children) do
        local cx = x + 8 + (i % cols) * 64
        local cy = y + 30 + math.floor(i / cols) * 64
        love.graphics.setColor(0.2, 0.3, 0.5)
        love.graphics.rectangle("fill", cx, cy, 56, 56)
        love.graphics.setColor(1, 1, 1)
        if data then
            love.graphics.print(data.itemId or id, cx + 4, cy + 4)
            if data.count then love.graphics.print("x" .. data.count, cx + 4, cy + 34) end
        end
        i = i + 1
    end
end

function M.draw()
    for _, b in ipairs(buttons) do
        love.graphics.setColor(0.3, 0.6, 0.9, 0.9)
        love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(b.label, b.x + 8, b.y + 6)
    end

    if M.panelsOpen.bag then
        local bag = views.get("bag")
        if bag then drawPanel("bag", bag.children, 5, 120, 30, 340, 150) end
    end
    if M.panelsOpen.equipment then
        local eq = views.get("equipment")
        if eq then drawPanel("equipment", eq.children, 3, 120, 200, 220, 110) end
    end
end

function M.mousepressed(x, y)
    for _, b in ipairs(buttons) do
        if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            M.toggleKey(b.key)
        end
    end
end

return M
