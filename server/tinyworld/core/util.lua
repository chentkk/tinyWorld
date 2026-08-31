-- tinyworld/core/util.lua
-- 常用工具函数。

local M = {}

M.pi2 = math.pi * 2

function M.round(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.distance(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

function M.copyShallow(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

function M.keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    return out
end

function M.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function M.merge(dst, src)
    for k, v in pairs(src or {}) do dst[k] = v end
    return dst
end

function M.alias(t, name)
    M.merge(t, { alias = name })
    if name then
        rawset(t, name, t)
    end
    return t
end

-- 生成唯一 id: appId 作为高位(appId * 2^32), 低 32 位为自增序号。
-- 纯整数运算, 避免依赖位运算库; 只要总数处在 Lua 53 位整数安全范围即可。
local seq = 0
function M.makeEntityId(appId)
    seq = (seq + 1) % 4294967296
    return appId * 4294967296 + seq
end

function M.entityAppId(entityId)
    return math.floor(entityId / 4294967296)
end

-- 时间工具, 秒级与毫秒级。
function M.now()
    return os.time()
end

function M.stamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

function M.randHex(bytes)
    bytes = bytes or 8
    local seed = tostring(os.time()) .. tostring(seq) .. tostring(math.random(1e9))
    local out = seed
    -- 简单散列, 生成确定长度的 hex token
    local h = 0
    for i = 1, #seed do
        h = (h * 31 + string.byte(seed, i)) % 2147483647
    end
    return string.format("%08x", h)
end

return M
