-- tinyworld/schema/object.lua
-- 容器子对象基类。与 Entity 类似, 子对象自身持有 props/records,
-- 字段写回自动通知 owner 容器, 产生同步 op。
-- 具体子对象(modifier/ability/item)可通过 Object.extend 增加业务行为。

local class = require "tinyworld.core.class"
local Properties = require "tinyworld.schema.property"
local Record = require "tinyworld.schema.record"

local Object = class.makeClass("Object")

-- 反序列化工厂(类方法): 由 Container 在加载/迁移时调用, 用于重建子对象实例。
-- 默认构造纯数据 Object; 带行为的子类(ability/modifier)覆盖此方法。
-- 只负责构造实例, props/records 仍由 Container 统一按 data 填充。
function Object.fromData(container, data)
    return Object.new(container.def.childSchema, container.def.childRecordDefs)
end

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

-- 反序列化(与 Entity:load 对称): 恢复可序列化状态。
-- data 为平铺结构: 命中 records 的键按行恢复, 其余按键写入 props。
function Object:load(data)
    for name, value in pairs(data or {}) do
        local rec = self.records[name]
        if rec then
            for _, row in pairs(type(value) == "table" and value or {}) do
                rec:add(row)
            end
        else
            self[name] = value
        end
    end
    return self
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

-- 子对象存盘导出: 仅保留 childDef 中 persist=true 的字段。
function Object:objectDataPersist()
    local out = {}
    for _, f in ipairs(self.props.schema.fields) do
        if f.persist and self.props.values[f.name] ~= nil then
            out[f.name] = self.props.values[f.name]
        end
    end
    return out
end

return Object
