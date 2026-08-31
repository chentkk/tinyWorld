-- tinyworld/combat/kv.lua
-- 极简 dota KV 解析器, 读取 npc/ 能力数据定义。
-- 支持 "DOTAAbilities" 外层块与按能力名切开内层数据。

local kv = {}

local function block(text, name)
    local startPos = text:find('"' .. name .. '"', 1, true)
    if not startPos then return nil end

    local open = text:find("{", startPos, true)
    if not open then return nil end

    local depth = 0
    local close
    for i = open, #text do
        local c = text:sub(i, i)
        if c == "{" then depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then close = i break end
        end
    end
    if not close then return nil end

    return text:sub(open + 1, close - 1)
end

-- 解析一个内层块为 table { key = value }
local function parseBlock(body)
    local out = {}
    for key, value in body:gmatch('"([%w_%.]+)"%s+"([^"]*)"') do
        out[key] = tonumber(value) or value
    end
    for key, value in body:gmatch('"([%w_%.]+)"%s+"([%d%.%-]+)"') do
        out[key] = tonumber(value)
    end
    return out
end

-- path 形如 "game/scripts/npc/heroes/abaddon/aphotic_shield.txt"
function kv.load(path, abilityName)
    local file = io.open(path, "r")
    if not file then return nil end
    local text = file:read("*a")
    file:close()

    abilityName = abilityName or text:match('"DOTAAbilities"%s*{%s*"([%w_]+)"')
    local body = block(text, abilityName)
    if not body then return nil end

    local data = parseBlock(body)
    data.name = abilityName
    return data
end

function kv.loadAbility(npcPath, abilityName)
    return kv.load(npcPath, abilityName)
end

return kv
