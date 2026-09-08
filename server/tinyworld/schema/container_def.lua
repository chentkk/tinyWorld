-- tinyworld/schema/container_def.lua
-- ContainerDef: 容器/视图定义。
-- 容器自身可携带 props / records; 子对象通过 childDef 定义(与 player/modifier 同结构)。

local class = require "tinyworld.core.class"
local PropertySchema = require "tinyworld.schema.property_schema"
local RecordDef = require "tinyworld.schema.record_def"

local ContainerDef = class.makeClass("ContainerDef")

function ContainerDef:ctor(def)
    self.name = def.name
    self.persist = def.persist == true
    self.selfOnly = def.selfOnly == true

    -- 容器自身定义: props + records
    self.propsSchema = PropertySchema.new(def.props or {})
    self.recordDefs = {}
    for _, rd in ipairs(def.records or {}) do
        self.recordDefs[#self.recordDefs + 1] = RecordDef.new(rd)
    end

    -- 子对象定义: childDef(与 player / modifier 同结构)
    local childDef = def.childDef or {}
    local childPropDef = childDef.props or {}
    local childRecordDef = childDef.records or {}
    self.childSchema = PropertySchema.new(childPropDef)
    self.childRecordDefs = {}
    for _, rd in ipairs(childRecordDef) do
        self.childRecordDefs[#self.childRecordDefs + 1] = RecordDef.new(rd)
    end
end

function ContainerDef:childId(data)
    return data.id or data[self:childIdField()]
end

function ContainerDef:childIdField()
    for _, f in ipairs(self.childSchema.fields) do
        if f.name == "id" then return "id" end
    end
    return "id"
end

return ContainerDef
