-- tinyworld/schema/container.lua
-- Container: 容器运行实例(打开同步后称为视图 View)。
-- 提供 add/remove/get 与视图同步 op。

local Record = require "tinyworld.schema.record"
local Object = require "tinyworld.schema.object"

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
    rawset(self, "order", {})
    rawset(self, "props", {})
    rawset(self, "propsSchema", def.propsSchema)
    rawset(self, "records", {})

    for _, rdef in ipairs(def.recordDefs) do
        rawget(self, "records")[rdef.name] = Record.new(rdef, self)
    end

    rawset(self, "viewId", nil)
    rawset(self, "dirty", {})
    rawset(self, "dirtyIndex", {})
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
    self.dirtyIndex = {}
end

function Container:closeView()
    self.isView = false
    self.viewId = nil
    self.dirty = {}
    self.dirtyIndex = {}
end

function Container:add(objOrData)
    local child = objOrData

    -- 兼容 old 用法: 传入 data table 时内部构造 Object
    if type(objOrData) ~= "table" or rawget(objOrData, "_schema") == nil then
        local data = objOrData or {}
        child = Object.new(self.def.childSchema, self.def.childRecordDefs)
        for name, value in pairs(data) do
            child[name] = value
        end
    end

    local id = child:objectId()
    if id == nil then
        error(self.def.name .. " child missing id")
    end
    if self.children[id] then
        return false
    end

    child:attach(self, id)
    self.children[id] = child
    if not child.__seen then
        self.order[#self.order + 1] = id
        child.__seen = true
    end

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

    return child
end

function Container:remove(id)
    if not self.children[id] then
        return false
    end

    self.children[id] = nil
    for i, ordId in ipairs(self.order) do
        if ordId == id then
            table.remove(self.order, i)
            break
        end
    end

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

function Container:childrenList()
    local out = {}
    for _, id in ipairs(self.order or {}) do
        local child = self.children[id]
        if child then out[#out + 1] = child end
    end
    return out
end

-- 子对象属性写回入口: 同一 flush 周期内同一子对象只保留一个 set op
function Container:onChildPropChange(child, name, value)
    local id = child:objectId()

    if self.isView then
        local idx = self.dirtyIndex[id]
        if idx and self.dirty[idx] and self.dirty[idx].type == "set" then
            self.dirty[idx].data[name] = value
        else
            local op = { type = "set", id = id, data = { [name] = value } }
            self.dirty[#self.dirty + 1] = op
            self.dirtyIndex[id] = #self.dirty
        end
    end
    if self.host and self.host.onContainerPersist then
        self.host:onContainerPersist(self)
    end
end

function Container:childFullData(child)
    local out = { id = child:objectId() }

    for k, v in pairs(child:objectData() or {}) do
        out[k] = v
    end
    for name, rec in pairs(child.records or {}) do
        out[name] = rec:dump()
    end

    return out
end

function Container:collectSync()
    local ops = self.dirty
    self.dirty = {}
    self.dirtyIndex = {}
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
