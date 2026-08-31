-- tinyworld/net/msg.lua
-- 消息构造与 message.log 格式化工具。

local proto = require "tinyworld.core.proto"
local M = {}

function M.new(t, n, d)
    return { t = t, n = n, d = d or {} }
end

local function pad(v)
    if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then
        return tostring(v)
    end
    return ""
end

local function isArray(t)
    if type(t) ~= "table" then return false end
    local n = #t
    if n == 0 then return next(t) == nil end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

-- op <type> <data fields ...> <other fields ...>, 适合 view/record 同步日志
local function formatOp(op)
    local opType = op.type
    local parts = {}
    if opType ~= nil then parts[#parts + 1] = tostring(opType) end

    local data = op.data
    if type(data) == "table" then
        for k, v in pairs(data) do
            parts[#parts + 1] = tostring(k) .. "=" .. pad(v)
        end
    end

    for k, v in pairs(op) do
        if k ~= "type" and k ~= "data" then
            if k == "id" and type(data) == "table" and data.id == v then
                -- op 自身 id 与 data.id 重复时跳过
            else
                parts[#parts + 1] = tostring(k) .. "=" .. pad(v)
            end
        end
    end
    return table.concat(parts, " ")
end

-- 递归扁平化。数组元素标记为 object<i>, op 按 add/set/remove 展开
local function flatten(t, depth)
    if type(t) ~= "table" then return pad(t) end
    if depth > 3 then return "..." end

    if isArray(t) then
        local parts = {}
        for i, v in ipairs(t) do
            parts[#parts + 1] = "object<" .. i .. ">={" .. flatten(v, depth + 1) .. "}"
        end
        return table.concat(parts, " ")
    end

    if t.type ~= nil then
        return formatOp(t)
    end

    local parts = {}
    for k, v in pairs(t) do
        if k == "ops" and type(v) == "table" and isArray(v) then
            for i, op in ipairs(v) do
                parts[#parts + 1] = "object<" .. i .. ">={" .. flatten(op, depth + 1) .. "}"
            end
        elseif type(v) == "table" then
            parts[#parts + 1] = tostring(k) .. "={" .. flatten(v, depth + 1) .. "}"
        else
            parts[#parts + 1] = tostring(k) .. "=" .. pad(v)
        end
    end
    return table.concat(parts, " ")
end

function M.logData(data)
    return flatten(data, 0)
end

function M.encodeBody(msg)
    return proto.encode(msg)
end

M.proto = proto
return M
