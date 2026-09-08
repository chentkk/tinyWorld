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

    -- AOI 视野表: 以服务器实体 id 为索引。客户端显示 id 统一使用 getRealId(),
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
    if schema and schema:get(key) then
        if rawget(self, key) ~= nil then
            error("schema field must not be rawset: " .. tostring(key))
        end
        if self.props then
            local v = self.props:get(key)
            if v ~= nil then return v end
        end
    end
    return Entity[key]
end

function Entity:set(name, value, source)
    self.props:set(name, value, source)
end

function Entity:get(name)
    return self.props:get(name)
end

-- 是否允许跨 cell 迁移。瞬态/特殊实体可通过 def.migratable=false 关闭。
-- migratable 只影响 checkMigrations, 不影响 ghost 创建(ghost 判定见 canGhost)。
function Entity:canMigrate()
    return not (self.def and self.def.migratable == false)
end

-- 是否为网络对象(客户端可感知)。
-- networked=false 的对象只存在于服务器, 不进 outbox / ghost / visibility,
-- 客户端完全无法感知其生命周期。
function Entity:isNetworked()
    return not (self.def and self.def.networked == false)
end

-- 是否可为其他 cell 创建 ghost。默认所有 cell entity 都需要 ghost;
-- 短生命周期对象(如 projectile)可以不迁移, 但仍需要 ghost 机制同步给其他 cell。
-- 纯服务器对象(networked=false)完全不需要 ghost。
function Entity:canGhost()
    if not self:isNetworked() then return false end
    return not (self.def and self.def.ghostable == false)
end

-- 客户端视角的权威实体 id。Real 返回自身 id, Ghost 返回真身 realId。
function Entity:getRealId()
    return self.id
end

function Entity:getRecord(name)
    return self.records[name]
end

-- entity 级定时器(由所在 cell 的时间轮托管)
-- delay 秒; times=-1 无限, 其他为总触发次数(缺省 1)
function Entity:addTimer(delay, times, fn)
    local cell = assert(rawget(self, "cell"), "entity not bound to a cell")
    return cell:addTimer(self, delay, times, fn)
end

function Entity:removeTimer(timerId)
    local cell = assert(rawget(self, "cell"), "entity not bound to a cell")
    return cell:removeTimer(timerId)
end

-- 对象分类标签(来自 def.tags, 构造时已 normalize)
function Entity:hasTag(tag)
    local tagMod = require "tinyworld.core.tag"
    return tagMod.has(self.def and self.def.tags, tag)
end

function Entity:hasAnyTag(tags)
    local tagMod = require "tinyworld.core.tag"
    return tagMod.hasAny(self.def and self.def.tags, tags)
end

function Entity:hasAllTags(tags)
    local tagMod = require "tinyworld.core.tag"
    return tagMod.hasAll(self.def and self.def.tags, tags)
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

-- 按 def 配置装配组件: componentsConfig = { {name="move", module="game.cell.move"}, ... }
function Entity:setupComponents(componentsConfig)
    for _, conf in ipairs(componentsConfig or {}) do
        local modulePath
        local name
        if type(conf) == "string" then
            modulePath = conf
            name = modulePath:match("([^%.]+)$") or modulePath
        else
            modulePath = conf.module
            name = conf.name or modulePath:match("([^%.]+)$")
        end
        assert(modulePath, "component config missing module")
        self:addComponent(name, require(modulePath))
    end
end

-- 打开 def 配置中声明的容器视图
function Entity:openViews(viewNames)
    for _, viewName in ipairs(viewNames or {}) do
        local cont = self.containers[viewName]
        if cont then cont:openView(viewName) end
    end
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

-- 请求销毁: 触发 onDestroy 并离开当前 cell
function Entity:destroy()
    if rawget(self, "_destroyed") then return end
    rawset(self, "_destroyed", true)

    self:onDestroy()
    if self.cell and self.cell.removeEntity then
        self.cell:removeEntity(self)
    end
end

function Entity:onEnterCell(cell)
    self.cell = cell
    self:emit("on_enter_cell", cell)
    self:eachComponent(function(_, comp)
        if comp.onEnterCell then comp:onEnterCell(cell) end
    end)
end

-- 迁移离开回调(本地 / 跨 cellapp 迁移前调用, 用于业务清理)
function Entity:onMigrateOut(cell)
    self:emit("on_migrate_out", cell)
    self:eachComponent(function(_, comp)
        if comp.onMigrateOut then comp:onMigrateOut(cell) end
    end)
end

-- 迁移完成回调(本地 / 跨 cellapp 迁移在组件重新装配后调用)
function Entity:onMigrateIn(cell)
    self:emit("on_migrate_in", cell)
    self:eachComponent(function(_, comp)
        if comp.onMigrateIn then comp:onMigrateIn(cell) end
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
        local contRecords = {}
        for recName, rec in pairs(cont.records or {}) do
            contRecords[recName] = rec:dump()
        end
        containers[name] = { props = cont.props, records = contRecords, children = cont:dump() }
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
            cont.props = saved.props or {}
            for recName, rows in pairs(saved.records or {}) do
                local rec = cont.records and cont.records[recName]
                if rec then
                    for _, row in pairs(rows) do rec:add(row) end
                end
            end
            cont:load(saved.children)
        end
    end
end

return Entity
