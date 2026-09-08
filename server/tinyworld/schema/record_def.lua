-- tinyworld/schema/record_def.lua
-- RecordDef: 表格定义(主键字段 / 同步方式 / 字段 schema)。

local class = require "tinyworld.core.class"
local PropertySchema = require "tinyworld.schema.property_schema"

local RecordDef = class.makeClass("RecordDef")

function RecordDef:ctor(def)
    self.name = def.name
    self.keyFields = def.keyFields or { def.key or "key" }
    self.sync = def.sync or "none"
    self.schema = PropertySchema.new(def.fields or {})
    self.indexes = def.indexes or {}
end

function RecordDef:keyOf(data)
    local parts = {}
    for _, k in ipairs(self.keyFields) do parts[#parts + 1] = tostring(data[k]) end
    return table.concat(parts, ":")
end

return RecordDef
