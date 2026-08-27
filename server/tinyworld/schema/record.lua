-- tinyworld/schema/record.lua
-- Record: 表格运行实例, 支持 add/remove/query/set/get, 提供同步 ops。

local Record = {}
Record.__index = Record

function Record.new(def, host)
    local self = setmetatable({}, Record)
    self.def = def
    self.host = host
    self.rows = {}
    self.dirty = {}
    return self
end

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
    if self.host.onRecordChange then self.host:onRecordChange(self, { type = "add", key = key }) end
    return row
end

function Record:remove(key)
    local row = self.rows[key]
    if not row then return false end

    self.rows[key] = nil
    if self.def.sync ~= "none" then self.dirty[#self.dirty + 1] = { type = "remove", key = key } end
    if self.host.onRecordChange then self.host:onRecordChange(self, { type = "remove", key = key }) end
    return true
end

function Record:get(key) return self.rows[key] end

function Record:count()
    local n = 0
    for _ in pairs(self.rows) do n = n + 1 end
    return n
end

function Record:update(key, patch)
    local row = self.rows[key]
    if not row then return nil end

    for name, value in pairs(patch) do row[name] = self.def.schema:coerce(name, value) end
    if self.def.sync ~= "none" then self.dirty[#self.dirty + 1] = { type = "set", key = key, data = patch } end
    if self.host.onRecordChange then self.host:onRecordChange(self, { type = "set", key = key }) end
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
        if not pred or pred(row, key) then out[#out + 1] = row end
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
        if f.sync ~= "none" and row[f.name] ~= nil then out[f.name] = row[f.name] end
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

return Record
