-- tinyworld/schema/container.lua
-- Container: 容器运行实例(打开同步后称为视图 View)。
-- 提供 add/remove/get 与视图同步 op。

local class = require "tinyworld.core.class"
local Record = require "tinyworld.schema.record"
local Object = require "tinyworld.schema.object"

local Container = class.makeClass("Container")

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

function Container:__index(key)
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
end

function Container:__newindex(key, value)
    local schema = rawget(self, "propsSchema")
    if schema and schema:get(key) then
        setContainerProp(self, key, value)
        return
    end
    rawset(self, key, value)
end

function Container:ctor(def, host)
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

    -- 子对象类(可选): 反序列化时重建带行为子对象, 见 ContainerDef.childClass。
    rawset(self, "childClass", Object)
    if def.childClass then
        rawset(self, "childClass", require(def.childClass))
    end
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

-- 子对象构建分三步, 与 cell entity 构建(new -> load -> addEntity)对齐:
--   1) newChild(data)   构造实例(带行为的子类走 childClass.fromData)
--   2) child:load(data) 恢复可序列化状态(Object:load)
--   3) add(child)       登记入库 + 产生视图 op
-- 迁移/加载走 addFromData(三步串联); 业务创建(addModifier / createAbility)复用同一组步骤。

-- 第 3 步: 已构造好的子对象实例入库
function Container:add(child)
    assert(type(child) == "table" and rawget(child, "_schema") ~= nil,
        "Container.add expects an Object instance, use addFromData for tables")

    local id = child:objectId()
    if id == nil then
        error(self.def.name .. " child missing id")
    end
    if self.children[id] then
        return false
    end

    child:attach(self, id)
    self.children[id] = child
    self.order[#self.order + 1] = id

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

-- 第 1 步: 构造子对象实例。带行为的子类由 childClass.fromData 重建(ability/modifier),
-- 未声明 childClass 时返回默认纯数据 Object。
function Container:newChild(data)
    return self.childClass.fromData(self, data or {})
end

-- 第 1+2+3 步串联: 从纯数据恢复一个子对象并入库。
function Container:addFromData(data)
    data = data or {}
    local child = self:newChild(data)
    child:load(data)
    return self:add(child)
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

-- 子对象属性写回入口: 视图开启时合并同一子对象的 set op
function Container:onChildPropChange(child, name, value)
    if self.isView then
        self:mergeChildSet(child, name, value)
    end

    if self.host and self.host.onContainerPersist then
        self.host:onContainerPersist(self)
    end
end

function Container:pendingSetOp(id)
    local idx = self.dirtyIndex[id]
    local op = idx and self.dirty[idx]
    if op and op.type == "set" then
        return op
    end
    return nil
end

function Container:appendSetOp(id, name, value)
    local op = { type = "set", id = id, data = { [name] = value } }
    self.dirty[#self.dirty + 1] = op
    self.dirtyIndex[id] = #self.dirty
    return op
end

function Container:mergeChildSet(child, name, value)
    local id = child:objectId()
    local op = self:pendingSetOp(id)
    if op then
        op.data[name] = value
    else
        self:appendSetOp(id, name, value)
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

-- 按插入顺序导出(与 childrenList 一致), 保证迁移/加载后子对象顺序稳定,
-- 客户端按 index 访问(如技能施放)才不会因序列化顺序漂移。
function Container:dump()
    local out = {}
    for _, id in ipairs(self.order or {}) do
        local child = self.children[id]
        if child then out[#out + 1] = self:childFullData(child) end
    end
    return out
end

-- 容器自身 props 存盘导出: 按 propsSchema 的 persist 字段过滤。
function Container:dumpPropsPersist()
    local out = {}
    for _, f in ipairs(self.propsSchema.fields) do
        if f.persist and self.props[f.name] ~= nil then
            out[f.name] = self.props[f.name]
        end
    end
    return out
end

-- 子对象存盘导出: 每个 child 只保留 persist=true 字段, 子 record 只保留 persist 表。
function Container:dumpPersist()
    local out = {}
    for _, id in ipairs(self.order or {}) do
        local child = self.children[id]
        if child then
            local data = { id = child:objectId() }
            for k, v in pairs(child:objectDataPersist() or {}) do
                data[k] = v
            end
            for recName, rec in pairs(child.records or {}) do
                if rec.def.persist then data[recName] = rec:dump() end
            end
            out[#out + 1] = data
        end
    end
    return out
end

function Container:load(list)
    for _, data in ipairs(list or {}) do
        self:addFromData(data)
    end
end

return Container
