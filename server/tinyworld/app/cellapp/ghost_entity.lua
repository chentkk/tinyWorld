-- tinyworld/app/cellapp/ghost_entity.lua
-- GhostEntity(幽灵): real 在其他 cell 的投影。
-- real.outbox 应用到 ghost 自身 props / records / containers,
-- 下一 tick ghost 与 real 一样统一打包给观察者。

local Entity = require "tinyworld.entity.entity"

local GhostEntity = Entity.extend("GhostEntity")

function GhostEntity:ctor(def, id, kind, space, cell, realId, x, y)
    Entity.ctor(self, def, id, kind)
    self.isGhost = true
    self.isReal = false
    self.realId = realId
    self.clientId = realId -- 客户端看到的是真身 id
    self.space = space
    self.cell = cell
    self.x = x or 0
    self.y = y or 0
    self.realApp = nil
    self.realCellKey = nil
    self.pendingEvents = {}
end

function GhostEntity:applyOutbox(outbox)
    outbox = outbox or {}

    for name, value in pairs(outbox.aroundProps or outbox.props or {}) do
        self.props:set(name, value)
    end

    for name, ops in pairs(outbox.recordOps or {}) do
        self:applyRecordOps(name, ops)
    end

    for name, ops in pairs(outbox.viewOps or {}) do
        self:applyViewOps(name, ops)
    end

    for _, event in ipairs(outbox.events or {}) do
        self.pendingEvents[#self.pendingEvents + 1] = event
    end
end

function GhostEntity:applyRecordOps(name, ops)
    local rec = self.records[name]
    if not rec then return end

    for _, op in ipairs(ops or {}) do
        if op.type == "add" then rec:add(op.data)
        elseif op.type == "remove" then rec:remove(op.key)
        elseif op.type == "set" then rec:update(op.key, op.data or {}) end
    end
end

function GhostEntity:applyViewOps(name, ops)
    local cont = self.containers[name]
    if not cont then return end

    for _, op in ipairs(ops or {}) do
        if op.type == "add" then cont:add(op.data)
        elseif op.type == "remove" then cont:remove(op.id)
        elseif op.type == "set" then
            for k, v in pairs(op.data or {}) do cont:setChildProp(op.id, k, v) end
        elseif op.type == "view" then
            for k, v in pairs(op.data or {}) do cont:setViewProp(k, v) end
        end
    end
end

return GhostEntity
