-- client/src/records.lua
-- 通用表格(Record)客户端: add / remove / set 增量维护本地行。

local M = {}

M.records = {} -- entityId -> { name -> { key -> row } }

function M.apply(msg)
    local entityId = msg.d and msg.d.entityId
    if not entityId then return end

    local name = msg.n
    local d = msg.d or {}
    local byName = M.records[entityId]
    if not byName then
        byName = {}
        M.records[entityId] = byName
    end

    local rec = byName[name]
    if not rec then
        rec = {}
        byName[name] = rec
    end

    for _, op in ipairs(d.ops or {}) do
        if op.type == "add" then
            rec[op.key] = op.data
        elseif op.type == "remove" then
            rec[op.key] = nil
        elseif op.type == "set" then
            local row = rec[op.key]
            if row then
                for k, v in pairs(op.data or {}) do row[k] = v end
            end
        end
    end
end

function M.get(entityId, name)
    local byName = M.records[entityId]
    return byName and byName[name] or {}
end

return M
