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

-- 子对象/容器自身属性直接读写的辅助
local function setContainerProp(self, name, value)
    local props = rawget(self, "props")
    value = rawget(self, "propsSchema"):coerce(name, value)
    if props[name] == value then
        return
    end

    props[name] = value

    if rawget(self, "isView") then
        local dirty = rawget(self, "dirty")
        dirty[#dirty + 1] = { type = "view", data = { [name] = value } }
    end
    local host = rawget(self, "host")
    if host and host.onContainerPersist then
        host:onContainerPersist(self)
    end
end

function Container.new(def, host)
    local self = {}

    local meta = {
        __index = function(_, key)
            local raw = rawget(self, key)
            if raw ~= nil then
                return raw
            end

            local props = rawget(self, "props")
            local schema = rawget(self, "propsSchema")
            if schema and schema:get(key) then
                return props[key]
            end
            return Container[key]
        end,
        __newindex = function(_, key, value)
            local schema = rawget(self, "propsSchema")
            if schema and schema:get(key) then
                setContainerProp(self, key, value)
                return
            end
            rawset(self, key, value)
        end,
    }
    self = setmetatable(self, meta)

    rawset(self, "def", def)
    rawset(self, "host", host)
    rawset(self, "children", {})
    rawset(self, "props", {})
    rawset(self, "propsSchema", def.propsSchema)
    rawset(self, "records", {})

    for _, rdef in ipairs(def.recordDefs) do
        rawget(self, "records")[rdef.name] = Record.new(rdef, self)
    end

    rawset(self, "viewId", nil)
    rawset(self, "dirty", {})
    rawset(self, "isView", false)

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
