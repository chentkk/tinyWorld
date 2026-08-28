-- tinyworld/schema/container_def.lua
-- ContainerDef: 容器/视图定义。
-- 容器自身可携带 props / records; 子对象通过 childDef 定义(与 player/modifier 同结构)。

local PropertySchema = require "tinyworld.schema.property_schema"
local RecordDef = require "tinyworld.schema.record_def"

local ContainerDef = {}
ContainerDef.__index = ContainerDef

function ContainerDef.new(def)
    local self = setmetatable({}, ContainerDef)

    self.name = def.name
    self.persist = def.persist and true or false
    self.selfOnly = def.selfOnly and true or false

    -- 容器自身定义: props + records
    local props = def.props or def.viewProps or {}
    local records = def.records or {}
    self.propsSchema = PropertySchema.new(props)
    self.recordDefs = {}
    for _, rd in ipairs(records) do
        self.recordDefs[#self.recordDefs + 1] = RecordDef.new(rd)
    end

    -- 子对象定义: childDef 优先, 兼容旧 childProps / childRecords
    local childDef = def.childDef or {}
    local childProps = def.childProps or childDef.props or {}
    local childRecords = def.childRecords or childDef.records or {}
    self.childSchema = PropertySchema.new(childProps)
    self.childRecordDefs = {}
    for _, rd in ipairs(childRecords) do
        self.childRecordDefs[#self.childRecordDefs + 1] = RecordDef.new(rd)
    end

    return self
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
