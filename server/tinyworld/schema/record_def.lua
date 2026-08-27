-- tinyworld/schema/record_def.lua
-- RecordDef: 表格定义(主键字段 / 同步方式 / 字段 schema)。

local PropertySchema = require "tinyworld.schema.property_schema"

local RecordDef = {}
RecordDef.__index = RecordDef

function RecordDef.new(def)
    local self = setmetatable({}, RecordDef)
    self.name = def.name
    self.keyFields = def.keyFields or { def.key or "key" }
    self.sync = def.sync or "none"
    self.schema = PropertySchema.new(def.fields or {})
    self.indexes = def.indexes or {}
    return self
end

function RecordDef:keyOf(data)
    local parts = {}
    for _, k in ipairs(self.keyFields) do parts[#parts + 1] = tostring(data[k]) end
    return table.concat(parts, ":")
end

return RecordDef
