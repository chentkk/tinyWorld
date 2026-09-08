-- tinyworld/entity/entity_def.lua
-- 编译 *_def 文件: 增加 propSchema / recordDefs / containerDefs。

local PropertySchema = require "tinyworld.schema.property_schema"
local Record = require "tinyworld.schema.record"
local RecordDef = require "tinyworld.schema.record_def"
local ContainerDef = require "tinyworld.schema.container_def"
local tag = require "tinyworld.core.tag"

local function defineRecordStructs(def)
    local function registerDefs(seen, list)
        for _, rd in ipairs(list or {}) do
            if not seen[rd.name] then
                Record.define(rd)
                seen[rd.name] = true
            end
        end
    end

    local seen = {}
    registerDefs(seen, def.recordDefs)

    for _, cd in ipairs(def.containerDefs or {}) do
        registerDefs(seen, cd.recordDefs)
        registerDefs(seen, cd.childRecordDefs)
    end
end

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
    -- 启动期集中注册 Record 表结构(在创建任何实例之前)
    defineRecordStructs(def)

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
