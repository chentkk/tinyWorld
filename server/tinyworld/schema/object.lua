-- tinyworld/schema/object.lua
-- 容器子对象基类。与 Entity 类似, 子对象自身持有 props/records,
-- 字段写回自动通知 owner 容器, 产生同步 op。
-- 具体子对象(modifier/ability/item)可通过 Object.extend 增加业务行为。

local class = require "tinyworld.core.class"
local Properties = require "tinyworld.schema.property"
local Record = require "tinyworld.schema.record"

local Object = class.makeClass("Object")

function Object:ctor(schema, recordDefs)
    rawset(self, "_schema", schema)
    rawset(self, "_owner", nil)

    rawset(self, "props", Properties.new(schema))
    self.props.host = self

    rawset(self, "records", {})
    for _, rdef in ipairs(recordDefs or {}) do
        self.records[rdef.name] = Record.new(rdef, self)
    end
end

-- 属性 schema 字段读写
function Object:__index(key)
    local schema = rawget(self, "_schema")
    if schema and schema:get(key) and self.props then
        local value = self.props:get(key)
        if value ~= nil then return value end
    end
    return Object[key]
end

function Object:__newindex(key, value)
    local schema = rawget(self, "_schema")
    if schema and schema:get(key) then
        self.props:set(key, value)
        return
    end
    rawset(self, key, value)
end

function Object:onPropChange(name, value, mode, source)
    local owner = rawget(self, "_owner")
    if owner and owner.onChildPropChange then
        owner:onChildPropChange(self, name, value)
    end
end

function Object:onRecordChange(rec, op)
    -- 容器子对象 record 变化暂不额外处理, 同步由 owner 决定
end

function Object:objectId()
    local rawId = rawget(self, "_id")
    if rawId ~= nil then return rawId end
    return self.props:get("id")
end

function Object:attach(owner, id)
    rawset(self, "_owner", owner)
    rawset(self, "_id", id)
    return self
end

function Object:objectData()
    local out = {}
    for _, f in ipairs(self.props.schema.fields) do
        if self.props.values[f.name] ~= nil then
            out[f.name] = self.props.values[f.name]
        end
    end
    return out
end

return Object
