-- tinyworld/core/proto.lua
-- 协议层抽象。默认使用 JSON, 之后可扩展 sproto, 业务无需改动。
-- 网络帧: 2 字节小端长度 + 负载。gate 只搬运原始负载, 不做解码, 减少拷贝。

local M = {}

M.codecName = "json"
M.codec = require "tinyworld.core.json"

function M.encode(t)
    return M.codec.encode(t)
end

function M.decode(str)
    return M.codec.decode(str)
end

function M.pack(t)
    local body = M.encode(t)
    return string.pack("<I2", #body) .. body
end

-- 从读缓冲中切出完整的帧。返回 nil 表示数据不足。
function M.popFrame(buf)
    if not buf or #buf < 2 then return nil end
    local len = string.unpack("<I2", buf, 1)
    if #buf < 2 + len then return nil end
    return len, buf:sub(3, 2 + len)
end

-- 仅生成完整网络帧(负载已是编码后的字符串, 避免二次拷贝)
function M.packBody(body)
    return string.pack("<I2", #body) .. body
end

-- 消息信封: { t=类型, n=名称, d=数据 }
function M.makeMsg(msgType, name, data)
    return { t = msgType, n = name, d = data or {} }
end

return M
