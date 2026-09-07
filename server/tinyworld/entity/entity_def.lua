-- tinyworld/entity/entity_def.lua
-- 编译 *_def 文件: 增加 propSchema / recordDefs / containerDefs。

local PropertySchema = require "tinyworld.schema.property_schema"
local RecordDef = require "tinyworld.schema.record_def"
local ContainerDef = require "tinyworld.schema.container_def"
local tag = require "tinyworld.core.tag"

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

    -- 组件/视图装配配置(由 def 文件声明的数据, 不包含业务逻辑)
    def.baseComponents = def.baseComponents or {}
    def.baseOpenViews = def.baseOpenViews or {}
    def.cellComponents = def.cellComponents or {}
    def.cellOpenViews = def.cellOpenViews or {}

    -- 对象分类标签(静态, 用于目标筛选/能力匹配)
    -- compileDef 在 def module 表上执行, 可能被重复注册; 用 rawTags 保留原始数组, 保证幂等
    if def.rawTags == nil then
        def.rawTags = def.tags
    end
    def.tags = tag.normalize(def.rawTags)
    return def
end
