-- tinyworld/schema/record.lua
-- Record: 表格运行实例, 支持 add/remove/query/set/get, 提供同步 ops。
-- 行对象支持 record[key].field = value 自动产生同步 op。

local RecordRow = require "tinyworld.schema.record_row"

local Record = {}
Record.__index = Record

function Record.new(def, host)
    local self = {}

    local instanceMeta = {
        __index = function(_, key)
            local rows = rawget(self, "rows")
            local row = rows and rows[key]
            if row then
                return row
            end
            return Record[key]
        end,
    }
    self = setmetatable(self, instanceMeta)

    rawset(self, "def", def)
    rawset(self, "host", host)
    rawset(self, "rows", {})
    rawset(self, "order", {})
    rawset(self, "dirty", {})      -- 待同步 op 数组(按 key 合并后仍有序)
    rawset(self, "dirtyIndex", {}) -- key -> dirty 数组下标

    return self
end

-- 移除 idx 位置的 op, 用末位元素填补空洞, 保持 dirty 数组密集
local function compactDirty(self, idx)
    local dirty = rawget(self, "dirty")
    local index = rawget(self, "dirtyIndex")
    local removed = dirty[idx]

    local last = dirty[#dirty]
    if last and last ~= removed then
        dirty[idx] = last
        dirty[#dirty] = nil
        index[last.key] = idx
    else
        dirty[#dirty] = nil
    end
    if removed and removed.key then
        index[removed.key] = nil
    end
    return removed
end

local function discardOp(self, key)
    local index = rawget(self, "dirtyIndex")
    local idx = index[key]
    if idx then
        return compactDirty(self, idx)
    end
end

local function appendOp(self, op)
    local dirty = rawget(self, "dirty")
    local index = rawget(self, "dirtyIndex")
    local idx = #dirty + 1
    dirty[idx] = op
    if op.key then
        index[op.key] = idx
    end
end

function Record:add(data)
    local schema = self.def.schema
    local key = self.def:keyOf(data)

    if rawget(self, "rows")[key] then
        return nil
    end

    local row = RecordRow.new(schema, self, key, data)

    rawget(self, "rows")[key] = row
    rawget(self, "order")[#rawget(self, "order") + 1] = key

    if self.def.sync ~= "none" then
        local index = rawget(self, "dirtyIndex")
        local pendingIdx = index[key]
        local pending = pendingIdx and rawget(self, "dirty")[pendingIdx]
        if pending and pending.type == "add" then
            pending.data = self:syncData(row)
        else
            if pending and pending.type == "remove" then
                discardOp(self, key)
            end
            appendOp(self, {
                type = "add",
                key = key,
                data = self:syncData(row),
            })
        end
    end
    if self.host and self.host.onRecordChange then
        self.host:onRecordChange(self, { type = "add", key = key })
    end

    return row
end

function Record:remove(key)
    local rows = rawget(self, "rows")
    if not rows[key] then
        return false
    end

    rows[key] = nil

    local order = rawget(self, "order")
    for i, k in ipairs(order) do
        if k == key then
            table.remove(order, i)
            break
        end
    end

    if self.def.sync ~= "none" then
        local index = rawget(self, "dirtyIndex")
        local pendingIdx = index[key]
        local pending = pendingIdx and rawget(self, "dirty")[pendingIdx]
        if pending and pending.type == "add" then
            discardOp(self, key)
        else
            if pending then
                discardOp(self, key)
            end
            appendOp(self, { type = "remove", key = key })
        end
    end
    if self.host and self.host.onRecordChange then
        self.host:onRecordChange(self, { type = "remove", key = key })
    end

    return true
end

function Record:get(key)
    return rawget(self, "rows")[key]
end

function Record:count()
    local n = 0
    for _ in pairs(rawget(self, "rows")) do
        n = n + 1
    end
    return n
end

function Record:update(key, patch)
    local row = rawget(self, "rows")[key]
    if not row then
        return nil
    end

    for name, value in pairs(patch) do
        row[name] = value
    end
    return row
end

function Record:set(key, name, value)
    return self:update(key, { [name] = value })
end

function Record:rowsList()
    local rows = rawget(self, "rows")
    local order = rawget(self, "order")

    local out = {}
    for _, key in ipairs(order) do
        local row = rows[key]
        if row then
            out[#out + 1] = row
        end
    end
    return out
end

function Record:query(pred)
    local rows = rawget(self, "rows")
    local out = {}
    for key, row in pairs(rows) do
        if not pred or pred(row, key) then
            out[#out + 1] = row
        end
    end
    return out
end

function Record:findOne(field, value)
    local rows = rawget(self, "rows")
    for _, row in pairs(rows) do
        if row[field] == value then
            return row
        end
    end
end

-- RecordRow 写回入口: 行字段变化 -> 合并到该行当前待同步 op。
-- 同一 flush 周期内同一行只保留一个 op, 最终字段覆盖中间值。
function Record:onChildPropChange(child, name, value)
    local key = child:id()

    if self.def.sync ~= "none" then
        local index = rawget(self, "dirtyIndex")
        local pending = index[key] and rawget(self, "dirty")[index[key]]
        if pending then
            pending.data[name] = value
        else
            appendOp(self, {
                type = "set",
                key = key,
                data = { [name] = value },
            })
        end
    end
    if self.host and self.host.onRecordChange then
        self.host:onRecordChange(self, { type = "set", key = key })
    end
end

function Record:syncData(row)
    local out = {}
    local schema = self.def.schema
    for _, f in ipairs(schema.fields) do
        if f.sync ~= "none" then
            out[f.name] = row[f.name]
        end
    end
    return out
end

function Record:collectSync()
    local dirty = rawget(self, "dirty")
    rawset(self, "dirty", {})
    rawset(self, "dirtyIndex", {})
    return dirty
end

function Record:flushSync()
    local ops = self:collectSync()
    if #ops == 0 then
        return nil
    end
    return { name = self.def.name, ops = ops }
end

function Record:dump()
    local rows = rawget(self, "rows")
    local out = {}
    for k, row in pairs(rows) do
        out[k] = row:data()
    end
    return out
end

return Record
