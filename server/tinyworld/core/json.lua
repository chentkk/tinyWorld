-- tinyworld/core/json.lua
-- 极简 JSON 编解码器。默认协议使用 JSON, 可通过 proto 模块整体切换为 sproto。
-- 支持 object / array / string / number / boolean / null。

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

local function encodeValue(v)
    if type(v) == "table" then
        return M.encode(v)
    elseif type(v) == "string" then
        return encodeString(v)
    elseif type(v) == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then
            return string.format("%d", v)
        end
        return string.format("%.14g", v)
    elseif type(v) == "boolean" then
        return v and "true" or "false"
    end
    return "null"
end

function M.encode(value)
    local t = type(value)
    if t ~= "table" then
        return encodeValue(value)
    end

    local out = {}
    local isArray = true
    local max = 0
    local n = 0
    for k in pairs(value) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            isArray = false
            break
        end
        n = n + 1
        if k > max then max = k end
    end
    if isArray and max == n then
        for i = 1, n do
            out[i] = encodeValue(value[i])
        end
        return "[" .. table.concat(out, ",") .. "]"
    end

    for k, v in pairs(value) do
        if type(k) == "string" then
            out[#out + 1] = encodeString(k) .. ":" .. encodeValue(v)
        end
    end
    return "{" .. table.concat(out, ",") .. "}"
end

-- 解码部分
local function skipWs(s, i)
    while i <= #s do
        local c = s:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
            return i
        end
        i = i + 1
    end
    return i
end

local decodeValue

local function decodeString(s, i)
    i = i + 1 -- 跳过引号
    local out = {}
    while i <= #s do
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(out), i + 1
        elseif c == '\\' then
            i = i + 1
            local e = s:sub(i, i)
            if e == 'n' then out[#out + 1] = '\n'
            elseif e == 't' then out[#out + 1] = '\t'
            elseif e == 'r' then out[#out + 1] = '\r'
            elseif e == 'b' then out[#out + 1] = '\b'
            elseif e == 'f' then out[#out + 1] = '\f'
            elseif e == '\\' or e == '"' or e == '/' then out[#out + 1] = e
            elseif e == 'u' then
                local hex = s:sub(i + 1, i + 4)
                out[#out + 1] = string.char(tonumber(hex, 16))
                i = i + 4
            end
            i = i + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    error("unterminated string")
end

local function decodeNumber(s, i)
    local j = i
    while j <= #s and s:sub(j, j):match("[0-9eE%+%-%.]") do j = j + 1 end
    local num = tonumber(s:sub(i, j - 1))
    return num, j
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
        if c == ',' then
            i = i + 1
        elseif c == ']' then
            return out, i + 1
        else
            error("bad array")
        end
        i = skipWs(s, i)
    end
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
        if s:sub(i, i) ~= ':' then error("bad object") end
        i = i + 1
        local v
        v, i = decodeValue(s, skipWs(s, i))
        out[k] = v
        i = skipWs(s, i)
        local c = s:sub(i, i)
        if c == ',' then
            i = i + 1
        elseif c == '}' then
            return out, i + 1
        else
            error("bad object")
        end
        i = skipWs(s, i)
    end
end

function decodeValue(s, i)
    i = skipWs(s, i)
    local c = s:sub(i, i)
    if c == '"' then
        return decodeString(s, i)
    elseif c == '{' then
        return decodeObject(s, i)
    elseif c == '[' then
        return decodeArray(s, i)
    elseif c == 't' then
        return true, i + 4
    elseif c == 'f' then
        return false, i + 5
    elseif c == 'n' then
        return nil, i + 4
    end
    return decodeNumber(s, i)
end

function M.decode(str)
    if type(str) ~= "string" then return nil end
    local value, i = decodeValue(str, 1)
    i = skipWs(str, i)
    if i <= #str then error("trailing data") end
    return value
end

return M
