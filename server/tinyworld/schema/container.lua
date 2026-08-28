-- tinyworld/schema/container.lua
-- Container: 容器运行实例(打开同步后称为视图 View)。
-- 提供 add/remove/get 与视图同步 op。

local Record = require "tinyworld.schema.record"
local ChildObject = require "tinyworld.schema.child_object"

-- 包装子对象: 保留 props/records/id, 同时支持 obj.field = value
local function makeChildProxy(child)
    return setmetatable(child, {
        __index = function(self, key)
            if key == "props" then return rawget(self, "props") end
            if key == "records" then return rawget(self, "records") end
            if key == "id" then return rawget(self, "id") end

            local props = rawget(self, "props")
            return props[key]
        end,
        __newindex = function(self, key, value)
            if key == "props" or key == "records" or key == "id" then
                rawset(self, key, value)
                return
            end

            local props = rawget(self, "props")
            props[key] = value
        end,
    })
end

local Container = {}
Container.__index = Container

function Container.new(def, host)
    local self = setmetatable({}, Container)

    self.def = def
    self.host = host
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

function Container:setViewProp(name, value)
    local prop = self.viewProps or {}

    value = self.viewSchema:coerce(name, value)
    if prop[name] == value then
        return
    end

    prop[name] = value
    self.viewProps = prop

    if self.isView then
        self.dirty[#self.dirty + 1] = { type = "view", data = { [name] = value } }
    end
    if self.host and self.host.onContainerPersist then
        self.host:onContainerPersist(self)
    end
end

function Container:getViewProp(name)
    return self.viewProps and self.viewProps[name]
end

function Container:add(data)
    local id = data.id
    if id == nil then
        error(self.def.name .. " child missing id")
    end
    if self.children[id] then
        return false
    end

    local child = {
        id = id,
        props = ChildObject.new(self.def.childSchema, self, id, data),
        records = {},
    }

    -- 子对象包含表格 Record
    for _, rdef in ipairs(self.def.childRecordDefs) do
        child.records[rdef.name] = Record.new(rdef, self)
    end

    child = makeChildProxy(child)
    self.children[id] = child

    if self.isView then
        self.dirty[#self.dirty + 1] = {
            type = "add",
            id = id,
            data = self:childFullData(child),
        }
    end
    if self.host and self.host.onContainerPersist then
        self.host:onContainerPersist(self)
    end

    return true
end

function Container:remove(id)
    if not self.children[id] then
        return false
    end

    self.children[id] = nil

    if self.isView then
        self.dirty[#self.dirty + 1] = { type = "remove", id = id }
    end
    if self.host and self.host.onContainerPersist then
        self.host:onContainerPersist(self)
    end

    return true
end

function Container:get(id)
    return self.children[id]
end

function Container:count()
    local n = 0
    for _ in pairs(self.children) do
        n = n + 1
    end
    return n
end

function Container:has(id)
    return self.children[id] ~= nil
end

function Container:setChildProp(id, name, value)
    local child = self.children[id]
    if not child then
        return false
    end

    child.props[name] = value
    return true
end

function Container:getChildProp(id, name)
    local child = self.children[id]
    return child and child.props[name]
end

-- ChildObject 属性写回的入口
function Container:onChildPropChange(child, name, value)
    if self.isView then
        self.dirty[#self.dirty + 1] = {
            type = "set",
            id = child:id(),
            data = { [name] = value },
        }
    end
    if self.host and self.host.onContainerPersist then
        self.host:onContainerPersist(self)
    end
end

function Container:getChildRecord(id, name)
    local child = self.children[id]
    return child and child.records[name]
end

function Container:childFullData(child)
    local out = { id = child.id }

    for k, v in pairs(child.props:data()) do
        out[k] = v
    end
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
    if #ops == 0 then
        return nil
    end

    return {
        name = self.def.name,
        viewId = viewId or self.viewId,
        ops = ops,
    }
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

return Container
