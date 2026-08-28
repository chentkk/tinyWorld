-- tinyworld/schema/record.lua
-- Record: 表格运行实例, 支持 add/remove/query/set/get, 提供同步 ops。
-- 行对象支持 record[key].field = value 自动产生同步 op。

local ChildObject = require "tinyworld.schema.child_object"

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
    rawset(self, "dirty", {})

    return self
end

function Record:add(data)
    local schema = self.def.schema
    local key = self.def:keyOf(data)

    if rawget(self, "rows")[key] then
        return nil
    end

    local row = ChildObject.new(schema, self, key, data)

    rawget(self, "rows")[key] = row
    rawget(self, "order")[#rawget(self, "order") + 1] = key

    if self.def.sync ~= "none" then
        local dirty = rawget(self, "dirty")
        dirty[#dirty + 1] = {
            type = "add",
            key = key,
            data = self:syncData(row),
        }
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
        local dirty = rawget(self, "dirty")
        dirty[#dirty + 1] = { type = "remove", key = key }
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

-- ChildObject 写回入口: 行字段变化 -> 生成 set op
function Record:onChildPropChange(child, name, value)
    if self.def.sync ~= "none" then
        local dirty = rawget(self, "dirty")
        dirty[#dirty + 1] = {
            type = "set",
            key = child:id(),
            data = { [name] = value },
        }
    end
    if self.host and self.host.onRecordChange then
        self.host:onRecordChange(self, { type = "set", key = child:id() })
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
