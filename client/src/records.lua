-- client/src/records.lua
-- 通用表格(Record)客户端: add / remove / set 增量维护本地行。

local M = {}

M.records = {} -- name -> { key -> row }

function M.apply(msg)
    local name = msg.n
    local d = msg.d or {}
    local rec = M.records[name]
    if not rec then
        rec = {}
        M.records[name] = rec
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

function M.get(name)
    return M.records[name] or {}
end

return M
