-- tinyworld/core/tag.lua
-- 轻量 GameplayTag 系统(借鉴 GAS 的 gameplay tag 思想, 不做层级/网络同步)。
-- 目前只服务服务器侧的对象分类与目标筛选, 使用方式:
--   def.tags = { "enemy", "unit", "projectile" }
--   entity:hasTag("enemy")
--   entity:hasAnyTag({ "boss", "elite" })
--   entity:hasAllTags({ "unit", "hostile" })

local M = {}

function M.normalize(tags)
    local set = {}
    for _, tag in ipairs(tags or {}) do
        assert(type(tag) == "string" and tag ~= "", "tag must be non-empty string")
        set[tag] = true
    end
    return set
end

function M.has(tagSet, tag)
    return tagSet ~= nil and tagSet[tag] == true
end

function M.hasAny(tagSet, tags)
    for _, tag in ipairs(tags or {}) do
        if tagSet and tagSet[tag] then return true end
    end
    return false
end

function M.hasAll(tagSet, tags)
    for _, tag in ipairs(tags or {}) do
        if not (tagSet and tagSet[tag]) then return false end
    end
    return true
end

return M
