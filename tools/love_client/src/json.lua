-- client/src/json.lua
-- 极简 JSON 编解码(与服务器 tinyworld/core/json.lua 保持一致)。

local M = {}

local escapes = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function encodeString(s)
    return '"' .. s:gsub('[%c\\"]', function(c)
        return escapes[c] or string.format('\\u%04x', string.byte(c))
    end) .. '"'
end

local encodeValue

function M.encode(value)
    local t = type(value)
    if t == "string" then return encodeString(value) end
    if t == "number" then
        if value == math.floor(value) and math.abs(value) < 1e15 then
            return string.format("%d", value)
        end
        return string.format("%.14g", value)
    end
    if t == "boolean" then return value and "true" or "false" end
    if t ~= "table" then return "null" end

    local out, n, max = {}, 0, 0
    local isArray = true
    for k in pairs(value) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then isArray = false break end
        n = n + 1
        if k > max then max = k end
    end
    if isArray and max == n then
        for i = 1, n do out[i] = encodeValue(value[i]) end
        return "[" .. table.concat(out, ",") .. "]"
    end
    for k, v in pairs(value) do
        if type(k) == "string" then out[#out + 1] = encodeString(k) .. ":" .. encodeValue(v) end
    end
    return "{" .. table.concat(out, ",") .. "}"
end

encodeValue = M.encode

local decodeValue

local function skipWs(s, i)
    while i <= #s do
        local c = s:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then return i end
        i = i + 1
    end
    return i
end

local function decodeString(s, i)
    i = i + 1
    local out = {}
    while i <= #s do
        local c = s:sub(i, i)
        if c == '"' then return table.concat(out), i + 1 end
        if c == '\\' then
            i = i + 1
            local e = s:sub(i, i)
            if e == 'n' then out[#out + 1] = '\n'
            elseif e == 't' then out[#out + 1] = '\t'
            elseif e == 'r' then out[#out + 1] = '\r'
            elseif e == '\\' or e == '"' or e == '/' then out[#out + 1] = e
            elseif e == 'u' then out[#out + 1] = string.char(tonumber(s:sub(i+1,i+4),16)); i = i + 4 end
            i = i + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
end

local function decodeNumber(s, i)
    local j = i
    while j <= #s and s:sub(j, j):match("[0-9eE%+%-%.]") do j = j + 1 end
    return tonumber(s:sub(i, j - 1)), j
end

local function decodeObject(s, i)
    i = i + 1
    local out = {}
    i = skipWs(s, i)
    if s:sub(i, i) == '}' then return out, i + 1 end
    while true do
        i = skipWs(s, i)
        local k
        k, i = decodeString(s, i)
        i = skipWs(s, i)
        assert(s:sub(i, i) == ':')
        i = i + 1
        local v
        v, i = decodeValue(s, skipWs(s, i))
        out[k] = v
        i = skipWs(s, i)
        local c = s:sub(i, i)
        if c == ',' then i = i + 1
        elseif c == '}' then return out, i + 1 end
        i = skipWs(s, i)
    end
end

local function decodeArray(s, i)
    i = i + 1
    local out = {}
    i = skipWs(s, i)
    if s:sub(i, i) == ']' then return out, i + 1 end
    while true do
        local v
        v, i = decodeValue(s, skipWs(s, i))
        out[#out + 1] = v
        i = skipWs(s, i)
        local c = s:sub(i, i)
        if c == ',' then i = i + 1
        elseif c == ']' then return out, i + 1 end
        i = skipWs(s, i)
    end
end

function decodeValue(s, i)
    i = skipWs(s, i)
    local c = s:sub(i, i)
    if c == '"' then return decodeString(s, i) end
    if c == '{' then return decodeObject(s, i) end
    if c == '[' then return decodeArray(s, i) end
    if c == 't' then return true, i + 4 end
    if c == 'f' then return false, i + 5 end
    if c == 'n' then return nil, i + 4 end
    return decodeNumber(s, i)
end

function M.decode(str)
    local value, i = decodeValue(str, 1)
    return value
end

return M
