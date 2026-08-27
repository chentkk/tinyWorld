-- tinyworld/entity/entity_def.lua
-- 编译 *_def 文件: 增加 propSchema / recordDefs / containerDefs。

local PropertySchema = require "tinyworld.schema.property_schema"
local RecordDef = require "tinyworld.schema.record_def"
local ContainerDef = require "tinyworld.schema.container_def"

return function(defModuleOrTable)
    local def
    if type(defModuleOrTable) == "string" then
        def = require(defModuleOrTable)
    else
        def = defModuleOrTable
    end

    def.propSchema = PropertySchema.new(def.props or {})
    def.recordDefs = {}
    for _, rd in ipairs(def.records or {}) do
        def.recordDefs[#def.recordDefs + 1] = RecordDef.new(rd)
    end

    def.containerDefs = {}
    for _, cd in ipairs(def.containers or {}) do
        def.containerDefs[#def.containerDefs + 1] = ContainerDef.new(cd)
    end
    return def
end
