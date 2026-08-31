-- tinyworld/core/bin.lua
-- 实体数据打包: 将自身属性 / 表格 / 容器子对象打包成二进制块,
-- 存到 player_bin 表。格式: 魔数 + 三段长度前缀负载。

local proto = require "tinyworld.core.proto"
local M = {}

M.MAGIC = "TWB1"

local function packSection(t)
    if t == nil then return string.pack("<I4", 0) end
    local body = proto.encode(t)
    return string.pack("<I4", #body) .. body
end

function M.packEntity(data)
    local out = M.MAGIC
    out = out .. packSection(data.props or {})
    out = out .. packSection(data.records or {})
    out = out .. packSection(data.containers or {})
    return out
end

local function readSection(bin, pos)
    local len = string.unpack("<I4", bin, pos)
    pos = pos + 4
    if len == 0 then return {}, pos end
    local body = bin:sub(pos, pos + len - 1)
    return proto.decode(body), pos + len
end

function M.unpackEntity(bin)
    if type(bin) ~= "string" or bin:sub(1, 4) ~= M.MAGIC then return nil end
    local pos = 5
    local props
    props, pos = readSection(bin, pos)
    local records
    records, pos = readSection(bin, pos)
    local containers
    containers, pos = readSection(bin, pos)
    return { props = props, records = records, containers = containers }
end

return M
