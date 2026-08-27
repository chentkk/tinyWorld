-- tinyworld/schema/container_def.lua
-- ContainerDef: 容器/视图定义(容器属性 schema, 子对象属性 schema, 子对象表格定义)。

local PropertySchema = require "tinyworld.schema.property_schema"
local RecordDef = require "tinyworld.schema.record_def"

local ContainerDef = {}
ContainerDef.__index = ContainerDef

function ContainerDef.new(def)
    local self = setmetatable({}, ContainerDef)
    self.name = def.name
    self.persist = def.persist and true or false
    self.viewSchema = PropertySchema.new(def.viewProps or {})
    self.childSchema = PropertySchema.new(def.childProps or {})

    self.childRecordDefs = {}
    for _, rd in ipairs(def.childRecords or {}) do
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
