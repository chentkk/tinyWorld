-- tinyworld/entity/entity.lua
-- 实体基类。每类对象由 *_def 文件定义: 属性 / 表格 / 容器。
-- 对象布局三要素: 属性(Properties) + 表格(Record) + 容器/视图(Container)。
-- 实体支持组件、生命周期、事件、以及按字符串注册的多向 rpc。

local class = require "tinyworld.core.class"
local event = require "tinyworld.core.event"
local Properties = require "tinyworld.schema.property"
local Record = require "tinyworld.schema.record"
local Container = require "tinyworld.schema.container"
local rpc = require "tinyworld.entity.rpc"

local Entity = class.makeClass("Entity")

function Entity:ctor(def, id, kind)
    rawset(self, "id", id)
    rawset(self, "kind", kind or def.name)
    rawset(self, "def", def)

    rawset(self, "props", Properties.new(def.propSchema))
    self.props.host = self

    rawset(self, "records", {})
    for _, rdef in ipairs(def.recordDefs) do
        self.records[rdef.name] = Record.new(rdef, self)
    end

    rawset(self, "containers", {})
    for _, cdef in ipairs(def.containerDefs) do
        self.containers[cdef.name] = Container.new(cdef, self)
    end

    rawset(self, "rpc", {
        client = rpc.new(),
        cell = rpc.new(),
        base = rpc.new(),
        real = rpc.new(),
        ghost = rpc.new(),
    })

    rawset(self, "components", {})
    rawset(self, "event", event.new())

    -- AOI 视野表: 以服务器实体 id 为索引。clientId 只是为了特定客户端显示,
    -- 由下发消息统一转换(objectAddMsg / objectRemoveMsg / cell 消息)。
    rawset(self, "visibleEntities", {})
    rawset(self, "dirtyClient", {})
    rawset(self, "pendingEvents", {})
end

-- 元表: entity.level = 10 等价于 entity.props:set("level", 10)
function Entity:__newindex(key, value)
    local schema = self.def.propSchema
    if schema and schema:get(key) then
        self.props:set(key, value)
        return
    end
    rawset(self, key, value)
end

function Entity:__index(key)
    local schema = rawget(self, "def") and rawget(self, "def").propSchema
    if schema and schema:get(key) and self.props then
        local v = self.props:get(key)
        if v ~= nil then return v end
    end
    return Entity[key]
end

function Entity:set(name, value, source)
    self.props:set(name, value, source)
end

function Entity:get(name)
    return self.props:get(name)
end

function Entity:getRecord(name)
    return self.records[name]
end

function Entity:getContainer(name)
    return self.containers[name]
end

-- Real / Ghost 共用: 属性变更只记录一份脏表, 出包时按观察者范围过滤
function Entity:collectClientProps(forSelf)
    local out = {}
    local schema = self.def.propSchema
    for name, value in pairs(self.dirtyClient) do
        local f = schema:get(name)
        if not f then out[name] = value
        elseif forSelf or f.sync == "all" then out[name] = value end
    end
    return out
end

function Entity:clearClientDirty()
    self.dirtyClient = {}
end

-- 组件
function Entity:addComponent(name, compClass, ...)
    local comp
    if type(compClass) == "table" and compClass.new then
        comp = compClass.new(self, name)
    else
        comp = compClass
        comp.entity = self
        comp.name = name
    end
    if select("#", ...) > 0 and comp.init then comp:init(...) end
    self.components[name] = comp
    if comp.onCreate then comp:onCreate() end
    return comp
end

function Entity:getComponent(name)
    return self.components[name]
end

function Entity:eachComponent(fn)
    for name, comp in pairs(self.components) do
        fn(name, comp)
    end
end

-- 事件
function Entity:on(ev, fn)
    return self.event:on(ev, fn)
end

function Entity:emit(ev, ...)
    return self.event:emit(ev, ...)
end

-- rpc 注册 (组件提供自身与方法名字符串)
function Entity:registerClientRpc(target, methodName, needLogin)
    self.rpc.client:register(target, methodName, { needLogin = needLogin })
end

function Entity:registerCellRpc(target, methodName)
    self.rpc.cell:register(target, methodName)
end

function Entity:registerBaseRpc(target, methodName)
    self.rpc.base:register(target, methodName)
end

function Entity:registerRealRpc(target, methodName)
    self.rpc.real:register(target, methodName)
end

function Entity:registerGhostRpc(target, methodName)
    self.rpc.ghost:register(target, methodName)
end

function Entity:dispatchClientRpc(name, data)
    return self.rpc.client:dispatch(name, data)
end

function Entity:dispatchCellRpc(name, data)
    return self.rpc.cell:dispatch(name, data)
end

function Entity:dispatchBaseRpc(name, data)
    return self.rpc.base:dispatch(name, data)
end

function Entity:dispatchRealRpc(name, data)
    return self.rpc.real:dispatch(name, data)
end

function Entity:dispatchGhostRpc(name, data)
    return self.rpc.ghost:dispatch(name, data)
end

-- 属性变化钩子(默认: 通知组件)
function Entity:onPropChange(name, value, mode, source)
    if mode ~= "none" then self.dirtyClient[name] = value end
    self:emit("prop_change", name, value, mode, source)
    self:eachComponent(function(_, comp)
        if comp.onPropChange then comp:onPropChange(name, value, mode, source) end
    end)
end

function Entity:onRecordChange(rec, op)
    self:emit("record_change", rec.def.name, op)
end

function Entity:onContainerPersist(cont)
    -- 基类不处理存盘, 由 RealEntity / BaseEntity 重写
end

-- 生命周期
function Entity:onCreate()
    self:emit("on_create")
    self:eachComponent(function(_, comp)
        if comp.onCreate then comp:onCreate() end
    end)
end

function Entity:onDestroy()
    self:emit("on_destroy")
    self:eachComponent(function(_, comp)
        if comp.onDestroy then comp:onDestroy() end
    end)
end

function Entity:onEnterCell(cell)
    self.cell = cell
    self:emit("on_enter_cell", cell)
    self:eachComponent(function(_, comp)
        if comp.onEnterCell then comp:onEnterCell(cell) end
    end)
end

function Entity:onLeaveCell(cell)
    self:emit("on_leave_cell", cell)
    self:eachComponent(function(_, comp)
        if comp.onLeaveCell then comp:onLeaveCell(cell) end
    end)
end

function Entity:onTick(dt)
    self:eachComponent(function(_, comp)
        if comp.onTick then comp:onTick(dt) end
    end)
end

function Entity:onClientEnter(playerId)
    self:emit("on_client_enter", playerId)
    self:eachComponent(function(_, comp)
        if comp.onClientEnter then comp:onClientEnter(playerId) end
    end)
end

function Entity:onClientLeave(playerId)
    self:emit("on_client_leave", playerId)
    self:eachComponent(function(_, comp)
        if comp.onClientLeave then comp:onClientLeave(playerId) end
    end)
end

-- 序列化: 属性 / 表格 / 容器 三块
function Entity:dump()
    local props = {}
    local schema = self.def.propSchema
    for _, f in ipairs(schema.fields) do
        if f.persist and self.props:get(f.name) ~= nil then
            props[f.name] = self.props:get(f.name)
        end
    end

    local records = {}
    for name, rec in pairs(self.records) do
        records[name] = rec:dump()
    end

    local containers = {}
    for name, cont in pairs(self.containers) do
        containers[name] = { viewProps = cont.viewProps, children = cont:dump() }
    end

    return { props = props, records = records, containers = containers }
end

function Entity:load(data)
    data = data or {}
    if data.props then self.props:load(data.props) end

    for name, rec in pairs(self.records) do
        local rows = data.records and data.records[name]
        for _, row in pairs(rows or {}) do
            rec:add(row)
        end
    end

    for name, cont in pairs(self.containers) do
        local saved = data.containers and data.containers[name]
        if saved then
            cont.viewProps = saved.viewProps
            cont:load(saved.children)
        end
    end
end

return Entity
