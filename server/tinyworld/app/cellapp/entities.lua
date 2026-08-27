-- tinyworld/space/entities.lua
-- 空间内实体: RealEntity(真身) 与 GhostEntity(幽灵)。
-- Real 维护自身关联的 ghost 列表; 属性变更同步到 ghost,
-- ghost 在下一个 tick 把变更发给周围玩家。

local entityMod = require "tinyworld.entity.entity"
local combatUnit = require "tinyworld.combat.unit"
local class = require "tinyworld.core.class"
local M = {}

-- 客户端对象快照
local function clientProps(entity)
    local out = {}
    local schema = entity.def.propSchema
    for _, f in ipairs(schema.fields) do
        if f.sync ~= "none" and entity.props:get(f.name) ~= nil then
            out[f.name] = entity.props:get(f.name)
        end
    end
    return out
end

M.clientProps = clientProps

-- 下发对象新增 message
function M.objectAddMsg(entity)
    return { t = "object", n = "add", d = {
        entityId = entity.clientId or entity.id, kind = entity.kind, props = clientProps(entity),
        modifiers = combatUnit.modifiersSnapshot(entity) } }
end

function M.objectRemoveMsg(entity)
    return { t = "object", n = "remove", d = { entityId = entity.clientId or entity.id } }
end

local RealEntity = entityMod.Entity.extend("RealEntity")

function RealEntity:ctor(def, id, kind, space, cell, x, y)
    entityMod.Entity.ctor(self, def, id, kind)
    self.clientId = id
    self.isReal = true
    self.space = space
    self.cell = cell
    self.x = x or 0
    self.y = y or 0
    self.ghosts = {} -- 维护真实对象关联的 ghost 列表
    self.dirtyGhostProps = {}
    self.dirtyClient = {}
    self.moving = false
    self.lastMigrateTime = 0
    self.baseApp = nil
    self.readyForSync = false
    self.pendingEvents = {}
    self.extra = {}
end

function RealEntity:setPosition(x, y, source)
    local space = self.space
    x = math.max(space.bounds.x1, math.min(space.bounds.x2, x))
    y = math.max(space.bounds.y1, math.min(space.bounds.y2, y))
    self.x = x
    self.y = y
end

function RealEntity:setBaseApp(addr)
    self.baseApp = addr
end

-- 属性变化: 记录 ghost 同步候选 + 客户端广播候选
function RealEntity:onPropChanged(name, value, mode, source)
    if mode ~= "none" then
        self.dirtyClient[name] = value
    end
    if mode == "all" then
        self.dirtyGhostProps[name] = value
    end
end

-- override 基类钩子
function RealEntity:onPropChange(name, value, mode, source)
    if name == "x" or name == "y" then
        rawset(self, name, value)
    end
    self:onPropChanged(name, value, mode, source)
    self:emit("prop_change", name, value, mode, source)
    self:eachComponent(function(_, comp)
        if comp.onPropChange then comp:onPropChange(name, value, mode, source) end
    end)
end

function RealEntity:addGhost(ghostInfo)
    self.ghosts[ghostInfo.key] = ghostInfo
end

function RealEntity:removeGhost(key)
    self.ghosts[key] = nil
end

function RealEntity:collectClientProps(forSelf)
    local out = {}
    local schema = self.def.propSchema
    for name, value in pairs(self.dirtyClient) do
        local f = schema:get(name)
        if not f then out[name] = value
        elseif forSelf or f.sync == "all" then
            out[name] = value
        end
    end
    return out
end

function RealEntity:clearClientDirty()
    self.dirtyClient = {}
end

function RealEntity:collectGhostDirty()
    local out = self.dirtyGhostProps
    self.dirtyGhostProps = {}
    return out
end

function RealEntity:ghostSnapshot()
    return { props = self.props:dump(), records = self:dump().records, containers = self:dump().containers }
end

function RealEntity:applySnapshot(snap)
    if snap.props then self.props:load(snap.props) end
end

function RealEntity:onDestroy()
    entityMod.Entity.onDestroy(self)
end

local GhostEntity = entityMod.Entity.extend("GhostEntity")

function GhostEntity:ctor(def, id, kind, space, cell, realId, x, y)
    entityMod.Entity.ctor(self, def, id, kind)
    self.isGhost = true
    self.isReal = false
    self.realId = realId
    self.clientId = realId -- 对客户端暴露真身 id
    self.space = space
    self.cell = cell
    self.x = x or 0
    self.y = y or 0
    self.realApp = nil
    self.realCellKey = nil
    self.stageProps = {}
    self.stageRecords = {}
    self.stageViews = {}
    self.pendingEvents = {}
end

function GhostEntity:stageProp(name, value)
    if self.props:get(name) == value then return end
    self.props:set(name, value)
    self.stageProps[name] = value
end

function GhostEntity:stageRecord(name, ops)
    local rec = self.records[name]
    if not rec then return end

    local out = self.stageRecords[name]
    if not out then out = {}; self.stageRecords[name] = out end

    for _, op in ipairs(ops or {}) do
        if op.type == "add" then rec:add(op.data)
        elseif op.type == "remove" then rec:remove(op.key)
        elseif op.type == "set" then rec:update(op.key, op.data or {}) end
        out[#out + 1] = op
    end
end

function GhostEntity:stageView(name, ops)
    local cont = self.containers[name]
    if not cont then return end

    local out = self.stageViews[name]
    if not out then out = {}; self.stageViews[name] = out end

    for _, op in ipairs(ops or {}) do
        -- 视图 op 只落客户端数据结构, 容器实例按 op 应用
        out[#out + 1] = op
    end
end

-- Real 的本轮 outbox 应用到 ghost, 下一 tick ghost 再打包给观察者
function GhostEntity:applyOutbox(outbox)
    outbox = outbox or {}

    for name, value in pairs(outbox.aroundProps or outbox.props or {}) do
        self:stageProp(name, value)
    end

    for name, ops in pairs(outbox.recordOps or outbox.records or {}) do
        self:stageRecord(name, ops)
    end

    for name, ops in pairs(outbox.viewOps or outbox.views or {}) do
        self:stageView(name, ops)
    end

    for _, event in ipairs(outbox.events or {}) do
        self.pendingEvents[#self.pendingEvents + 1] = event
    end
end

function GhostEntity:collectStage()
    local out = self.stageProps
    self.stageProps = {}
    return out
end

function GhostEntity:collectStageRecords()
    local out = self.stageRecords
    self.stageRecords = {}
    return out
end

function GhostEntity:collectStageViews()
    local out = self.stageViews
    self.stageViews = {}
    return out
end

M.RealEntity = RealEntity
M.GhostEntity = GhostEntity
return M
