-- tinyworld/core/mockdb.lua
-- 内存数据库: 无 mysql 环境下用于测试的极简 SQL 子集实现。
-- 支持 CREATE TABLE / SELECT ... WHERE col=val / INSERT / UPDATE / DELETE。

local M = {}

M.tables = {}

local function matchConditions(rows, conds)
    local out = {}
    for _, row in ipairs(rows) do
        local ok = true
        for _, cond in ipairs(conds) do
            local v = row[cond.col]
            if v ~= cond.val then ok = false break end
        end
        if ok then out[#out + 1] = row end
    end
    return out
end

local function parseWhere(sql)
    local wpos = sql:lower():find("where", 1, true)
    if not wpos then return {} end
    local conds = {}
    local where = sql:sub(wpos + 5)
    for col, val in where:gmatch("([%w_]+)%s*=%s*'([^']*)'") do
        conds[#conds + 1] = { col = col, val = val }
    end
    for col, val in where:gmatch("([%w_]+)%s*=%s*(%-?%d+%.?%d*)") do
        conds[#conds + 1] = { col = col, val = tonumber(val) }
    end
    return conds
end

local function parseTable(sql)
    local ls = sql:lower()
    local t = ls:match("from%s+([%w_]+)")
    t = t or ls:match("into%s+([%w_]+)")
    t = t or ls:match("update%s+([%w_]+)")
    t = t or ls:match("table%s+([%w_]+)")
    t = t or ls:match("delete%s+from%s+([%w_]+)")
    return t or "unknown"
end

function M.query(sql)
    local lowered = sql:lower()
    local tableName = parseTable(sql)
    local rows = M.tables[tableName] or {}

    if lowered:find("select") then
        if lowered:match("count%(") then
            return { { ["count(*)"] = #matchConditions(rows, parseWhere(sql)) } }
        end
        return matchConditions(rows, parseWhere(sql))
    end
    return matchConditions(rows, parseWhere(sql))
end

function M.exec(sql)
    local lowered = sql:lower()
    local tableName = parseTable(sql)

    if lowered:find("create%s+table") then
        M.tables[tableName] = M.tables[tableName] or {}
        return nil
    end

    if lowered:find("insert%s+into") then
        local colPart = sql:match("%b()")
        if not colPart then return nil end

        local cols = {}
        for col in colPart:gmatch("[%w_]+") do
            cols[#cols + 1] = col
        end

        local vpos = sql:lower():find("values")
        local valPart = sql:sub(vpos + 6)
        local vals = {}
        local i = 1
        while i <= #valPart do
            local c = valPart:sub(i, i)
            if c == "'" then
                local j = valPart:find("'", i + 1, true)
                if not j then break end
                vals[#vals + 1] = valPart:sub(i + 1, j - 1)
                i = j + 1
            elseif c:match("[%-%d%.]") then
                local j = i
                while j <= #valPart and valPart:sub(j, j):match("[%-%d%.]") do j = j + 1 end
                vals[#vals + 1] = tonumber(valPart:sub(i, j - 1))
                i = j
            else
                i = i + 1
            end
        end

        local row = {}
        for i, col in ipairs(cols) do
            row[col] = vals[i]
        end
        M.tables[tableName] = M.tables[tableName] or {}
        M.tables[tableName][#M.tables[tableName] + 1] = row
        return #M.tables[tableName]
    end

    if lowered:find("update%s+") then
        local conds = parseWhere(sql)
        local set = {}
        for col, val in sql:gmatch("set%s+([%w_]+)%s*=%s*'([^']*)'") do set[col] = val end
        for col, val in sql:gmatch("set%s+([%w_]+)%s*=%s*(%-?%d+%.?%d*)") do set[col] = tonumber(val) end
        local rows = M.tables[tableName] or {}
        for _, row in ipairs(rows) do
            local match = true
            for _, cond in ipairs(conds) do
                if tostring(row[cond.col]) ~= tostring(cond.val) then match = false break end
            end
            if match then
                for col, v in pairs(set) do row[col] = v end
            end
        end
        return nil
    end

    if lowered:find("delete%s+from") then
        local conds = parseWhere(sql)
        local rows = M.tables[tableName] or {}
        local kept = {}
        for _, row in ipairs(rows) do
            local match = true
            for _, cond in ipairs(conds) do
                if tostring(row[cond.col]) ~= tostring(cond.val) then match = false break end
            end
            if not match then kept[#kept + 1] = row end
        end
        M.tables[tableName] = kept
        return nil
    end

    return nil
end

function M.execSql(sql)
    if sql:lower():find("select") then
        return M.query(sql)
    end
    return M.exec(sql)
end

function M.reset()
    M.tables = {}
end

return M
