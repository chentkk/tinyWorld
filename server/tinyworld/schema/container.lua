-- tinyworld/schema/container.lua
-- 通用容器组件(打开同步后称为视图 View)。
-- 容器自身有属性(PropertySchema)，子对象有属性与表格(Record)。
-- 支持存库 / 不存库，baseapp / cellapp 通用。
-- 同步 op 类型: add(子对象全量) / remove(子对象 id) / set(子对象属性) / view(视图自身属性)。

local property = require "tinyworld.schema.property"
local record = require "tinyworld.schema.record"
local M = {}

local ContainerDef = {}
ContainerDef.__index = ContainerDef

-- def: { name, persist=false, viewProps={...}, childProps={...}, childRecords={ recordDef... } }
function ContainerDef.new(def)
    local self = setmetatable({}, ContainerDef)
    self.name = def.name
    self.persist = def.persist and true or false
    self.viewSchema = property.PropertySchema.new(def.viewProps or {})
    self.childSchema = property.PropertySchema.new(def.childProps or {})

    self.childRecordDefs = {}
    for _, rd in ipairs(def.childRecords or {}) do
        local rdef = record.RecordDef.new(rd)
        self.childRecordDefs[#self.childRecordDefs + 1] = rdef
    end
    return self
end

function ContainerDef:childId(data)
    return data.id or data[self:childIdField()]
end

function ContainerDef:childIdField()
    for _, f in ipairs((self.childSchema).fields) do
        if f.name == "id" then return "id" end
    end
    return "id"
end

M.ContainerDef = ContainerDef

local Container = {}
Container.__index = Container

function Container.new(def, host)
    local self = setmetatable({}, Container)
    self.def = def
    self.host = host -- 需实现 onViewChange(container, op)
    self.children = {}
    self.viewProps = nil
    self.viewSchema = def.viewSchema
    self.viewId = nil
    self.dirty = {}
    self.isView = false
    return self
end

function Container:isViewOpened()
    return self.isView
end

function Container:getViewId()
    return self.viewId
end

function Container:openView(viewId)
    self.isView = true
    self.viewId = viewId
    self.dirty = {}
end

function Container:closeView()
    self.isView = false
    self.viewId = nil
    self.dirty = {}
end

-- 容器自身属性(视图属性)
function Container:setViewProp(name, value)
    local prop = self.viewProps or {}
    value = self.viewSchema:coerce(name, value)
    if prop[name] == value then return end

    prop[name] = value
    self.viewProps = prop
    if self.isView then
        self.dirty[#self.dirty + 1] = { type = "view", data = { [name] = value } }
    end
    if self.host.onContainerPersist then
        self.host:onContainerPersist(self)
    end
end

function Container:getViewProp(name)
    return self.viewProps and self.viewProps[name]
end

function Container:add(data)
    local id = data.id
    if id == nil then error(self.def.name .. " child missing id") end

    if self.children[id] then return false end

    local child = {
        id = id,
        props = {},
        records = {},
    }

    local childSchema = self.def.childSchema
    for _, f in ipairs(childSchema.fields) do
        local v = data[f.name]
        if v ~= nil then
            child.props[f.name] = childSchema:coerce(f.name, v)
        elseif f.default ~= nil then
            child.props[f.name] = f.default
        end
    end

    for _, rdef in ipairs(self.def.childRecordDefs) do
        local rec = record.Record.new(rdef, self)
        child.records[rdef.name] = rec
    end

    self.children[id] = child

    if self.isView then
        self.dirty[#self.dirty + 1] = { type = "add", id = id, data = self:childFullData(child) }
    end
    if self.host.onContainerPersist then
        self.host:onContainerPersist(self)
    end
    return true
end

function Container:remove(id)
    local child = self.children[id]
    if not child then return false end

    self.children[id] = nil
    if self.isView then
        self.dirty[#self.dirty + 1] = { type = "remove", id = id }
    end
    if self.host.onContainerPersist then
        self.host:onContainerPersist(self)
    end
    return true
end

function Container:get(id)
    return self.children[id]
end

function Container:count()
    local n = 0
    for _ in pairs(self.children) do n = n + 1 end
    return n
end

function Container:has(id)
    return self.children[id] ~= nil
end

function Container:setChildProp(id, name, value)
    local child = self.children[id]
    if not child then return false end

    value = self.def.childSchema:coerce(name, value)
    if child.props[name] == value then return false end

    child.props[name] = value
    if self.isView then
        self.dirty[#self.dirty + 1] = { type = "set", id = id, data = { [name] = value } }
    end
    if self.host.onContainerPersist then
        self.host:onContainerPersist(self)
    end
    return true
end

function Container:getChildProp(id, name)
    local child = self.children[id]
    return child and child.props[name]
end

function Container:getChildRecord(id, name)
    local child = self.children[id]
    return child and child.records[name]
end

function Container:childFullData(child)
    local out = { id = child.id }
    for k, v in pairs(child.props) do out[k] = v end
    for name, rec in pairs(child.records) do
        out[name] = rec:dump()
    end
    return out
end

function Container:collectSync()
    local ops = self.dirty
    self.dirty = {}
    return ops
end

function Container:flushSync(viewId)
    local ops = self:collectSync()
    if #ops == 0 then return nil end
    return { name = self.def.name, viewId = viewId or self.viewId, ops = ops }
end

function Container:dump()
    local out = {}
    for id, child in pairs(self.children) do
        out[#out + 1] = self:childFullData(child)
    end
    return out
end

function Container:load(list)
    for _, data in ipairs(list or {}) do
        self:add(data)
    end
end

M.Container = Container

return M
