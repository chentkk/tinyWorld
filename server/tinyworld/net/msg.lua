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

-- op <type> <data fields...> <other fields...>
local function formatOp(op)
    local parts = {}
    if op.type ~= nil then parts[#parts + 1] = tostring(op.type) end

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

local function appendField(parts, key, value)
    parts[#parts + 1] = tostring(key) .. "=" .. pad(value)
end

-- object add: entityId<id> kind prop=value ...
local function formatObjectAdd(d)
    local parts = {}
    if d.entityId ~= nil then
        parts[#parts + 1] = "entityId<" .. pad(d.entityId) .. ">"
    end
    parts[#parts + 1] = pad(d.kind)

    local props = d.props or {}
    for k, v in pairs(props) do
        appendField(parts, k, v)
    end
    return table.concat(parts, " ")
end

-- record/view: entityId<id> row/object<i>={...}
local function formatOps(d, elementName)
    local parts = {}
    if d.entityId ~= nil then
        parts[#parts + 1] = "entityId<" .. pad(d.entityId) .. ">"
    end

    for i, op in ipairs(d.ops or {}) do
        parts[#parts + 1] = elementName .. "<" .. i .. ">={" .. formatOp(op) .. "}"
    end
    return table.concat(parts, " ")
end

-- 其他普通数据
local function flatten(t, depth)
    if type(t) ~= "table" then return pad(t) end
    if depth > 3 then return "..." end

    if isArray(t) then
        local parts = {}
        for i, v in ipairs(t) do
            parts[#parts + 1] = "entry<" .. i .. ">={" .. flatten(v, depth + 1) .. "}"
        end
        return table.concat(parts, " ")
    end

    if t.type ~= nil then return formatOp(t) end

    local parts = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            parts[#parts + 1] = tostring(k) .. "={" .. flatten(v, depth + 1) .. "}"
        else
            appendField(parts, k, v)
        end
    end
    return table.concat(parts, " ")
end

function M.logData(data, msgType, msgName)
    if msgType == "object" and msgName == "add" and type(data) == "table" then
        return formatObjectAdd(data)
    end
    if msgType == "record" and type(data) == "table" then
        return formatOps(data, "row")
    end
    if msgType == "view" and type(data) == "table" then
        return formatOps(data, "object")
    end
    return flatten(data, 0)
end

function M.encodeBody(msg)
    return proto.encode(msg)
end

M.proto = proto
return M
