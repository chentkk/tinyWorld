-- tinyworld/app/cellapp/ghost_entity.lua
-- GhostEntity(幽灵): real 在其他 cell 的投影。
-- 接收 real.outbox 并存储, 下一 tick 由所在 cell 打包给观察者。

local Entity = require "tinyworld.entity.entity"
local GhostEntity = Entity.extend("GhostEntity")

function GhostEntity:ctor(def, id, kind, space, cell, realId, x, y)
    Entity.ctor(self, def, id, kind)
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

return GhostEntity
