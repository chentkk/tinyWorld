-- game/scripts/vscripts/combat/kv.lua
-- 极简 keyvalues 解析器, 用于加载 npc/ 下的能力数据定义文件。

local M = {}

function M.load(path)
    local file = io.open(path, "r")
    if not file then return nil end

    local text = file:read("*a")
    file:close()

    local out = { name = text:match('"([%w_]+)"') }
    for key, value in text:gmatch('"([%w_]+)"%s+"([^"]+)"') do
        if key ~= out.name then
            out[key] = tonumber(value) or value
        end
    end
    return out
end

return M
