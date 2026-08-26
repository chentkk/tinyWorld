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

-- 递归扁平化, 形如 key={k=v ..}, 与 message.log 示例一致
local function flatten(t, depth)
    if type(t) ~= "table" then return pad(t) end
    if depth > 3 then return "..." end

    local parts = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
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
