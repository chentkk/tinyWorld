-- tinyworld/schema/record.lua
-- 通用表格组件 Record。
-- 支持 add / remove / query / set / get，可同步客户端或仅服务器内部使用。
-- 同步下行需标记所属对象(entityId)，由实体统一派发 ops。

local property = require "tinyworld.schema.property"
local M = {}

local RecordDef = {}
RecordDef.__index = RecordDef

-- def: { name, keyFields={...}, sync="all"/"none", fields={ props 风格定义 } }
function RecordDef.new(def)
    local self = setmetatable({}, RecordDef)
    self.name = def.name
    self.keyFields = def.keyFields or { def.key or "key" }
    self.sync = def.sync or "none"
    self.schema = property.PropertySchema.new(def.fields or {})
    self.indexes = def.indexes or {}
    return self
end

function RecordDef:keyOf(data)
    local parts = {}
    for _, k in ipairs(self.keyFields) do
        parts[#parts + 1] = tostring(data[k])
    end
    return table.concat(parts, ":")
end

function RecordDef:keyData(key)
    local values = {}
    for _, v in ipairs({key:match("([^:]+)") }) do
        -- split 需要逐段, 简单用 gmatch
    end
    local i = 1
    for part in key:gmatch("([^:]+)") do
        local f = self.schema:get(self.keyFields[i])
        if f and f.type == "number" then
            values[self.keyFields[i]] = tonumber(part)
        else
            values[self.keyFields[i]] = part
        end
        i = i + 1
    end
    return values
end

M.RecordDef = RecordDef

local Record = {}
Record.__index = Record

function Record.new(def, host)
    local self = setmetatable({}, Record)
    self.def = def
    self.host = host -- 需实现 onRecordChange(record, op)
    self.rows = {}
    self.dirty = {}
    return self
end

-- 按 keyFields 补全默认值
function Record:newRow(data)
    local row = {}
    local schema = self.def.schema
    for _, f in ipairs(schema.fields) do
        if data[f.name] ~= nil then
            row[f.name] = schema:coerce(f.name, data[f.name])
        elseif f.default ~= nil then
            row[f.name] = f.default
        end
    end
    return row
end

function Record:add(data)
    local row = self:newRow(data)
    local key = self.def:keyOf(row)
    if self.rows[key] then return nil end

    self.rows[key] = row
    if self.def.sync ~= "none" then
        self.dirty[#self.dirty + 1] = { type = "add", key = key, data = self:syncData(row) }
    end
    if self.host.onRecordChange then
        self.host:onRecordChange(self, { type = "add", key = key })
    end
    return row
end

function Record:remove(key)
    local row = self.rows[key]
    if not row then return false end

    self.rows[key] = nil
    if self.def.sync ~= "none" then
        self.dirty[#self.dirty + 1] = { type = "remove", key = key }
    end
    if self.host.onRecordChange then
        self.host:onRecordChange(self, { type = "remove", key = key })
    end
    return true
end

function Record:get(key)
    return self.rows[key]
end

function Record:count()
    local n = 0
    for _ in pairs(self.rows) do n = n + 1 end
    return n
end

function Record:update(key, patch)
    local row = self.rows[key]
    if not row then return nil end
    for name, value in pairs(patch) do
        row[name] = self.def.schema:coerce(name, value)
    end
    if self.def.sync ~= "none" then
        self.dirty[#self.dirty + 1] = { type = "set", key = key, data = patch }
    end
    if self.host.onRecordChange then
        self.host:onRecordChange(self, { type = "set", key = key })
    end
    return row
end

function Record:set(key, name, value)
    return self:update(key, { [name] = value })
end

function Record:rowsList()
    local out = {}
    for _, row in pairs(self.rows) do out[#out + 1] = row end
    return out
end

function Record:query(pred)
    local out = {}
    for key, row in pairs(self.rows) do
        if not pred or pred(row, key) then
            out[#out + 1] = row
        end
    end
    return out
end

function Record:findOne(field, value)
    for _, row in pairs(self.rows) do
        if row[field] == value then return row end
    end
end

function Record:syncData(row)
    local out = {}
    local schema = self.def.schema
    for _, f in ipairs(schema.fields) do
        if f.sync ~= "none" and row[f.name] ~= nil then
            out[f.name] = row[f.name]
        end
    end
    return out
end

function Record:collectSync()
    local ops = self.dirty
    self.dirty = {}
    return ops
end

function Record:flushSync()
    local ops = self:collectSync()
    if #ops == 0 then return nil end
    return { name = self.def.name, ops = ops }
end

function Record:dump()
    local out = {}
    for k, v in pairs(self.rows) do out[k] = v end
    return out
end

M.Record = Record

return M
