-- tinyworld/schema/property.lua
-- Properties: 属性运行实例, 负责 set/get、同步脏标记、持久化脏标记。

local class = require "tinyworld.core.class"
local PropertySchema = require "tinyworld.schema.property_schema"

local Properties = class.makeClass("Properties")

function Properties:ctor(schema, host)
    self.schema = schema or PropertySchema.new({})
    self.host = host
    self.values = {}
    self.dirtySync = {}
    self.dirtyPersist = {}

    for _, f in ipairs(self.schema.fields) do
        if f.default ~= nil then self.values[f.name] = f.default end
    end
end

function Properties:get(name)
    return self.values[name]
end

function Properties:set(name, value, source)
    value = self.schema:coerce(name, value)
    if self.values[name] == value then return end

    self.values[name] = value
    local f = self.schema:get(name)
    if f.sync ~= "none" then
        self.dirtySync[name] = true
        if self.host.onPropChange then self.host:onPropChange(name, value, f.sync, source) end
    end
    if f.persist then self.dirtyPersist[name] = true end
end

function Properties:setBatch(t, source)
    for k, v in pairs(t) do self:set(k, v, source) end
end

function Properties:syncMode(name)
    local f = self.schema:get(name)
    return f and f.sync or "none"
end

function Properties:collectSync(scope)
    local out = {}
    for name in pairs(self.dirtySync) do
        local f = self.schema:get(name)
        if f and (scope == "all" or scope == "self" or f.sync == "all") then
            out[name] = self.values[name]
        end
    end
    self.dirtySync = {}
    return out
end

function Properties:collectPersist()
    local out = {}
    for name in pairs(self.dirtyPersist) do out[name] = self.values[name] end
    return out
end

function Properties:dump()
    local out = {}
    for _, f in ipairs(self.schema.fields) do
        if self.values[f.name] ~= nil then out[f.name] = self.values[f.name] end
    end
    return out
end

function Properties:load(t)
    self:setBatch(t, "load")
end

return Properties
