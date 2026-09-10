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
    local sync = def.sync or "all"
    if sync ~= "none" and sync ~= "self" and sync ~= "all" then
        error("container sync must be none/self/all: " .. tostring(def.name))
    end
    self.sync = sync

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

    -- 子对象类: 反序列化(迁移/加载)时用于重建带行为的子对象(ability/modifier 等)。
    -- 值为扩展自 Object 的类模块路径; 该类需实现 fromData(container, data)。
    -- 未声明时使用默认 Object(纯数据子对象, 如 item)。
    self.childClass = childDef.class
end

return ContainerDef
