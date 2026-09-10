-- tinyworld/app/cellapp/ghost_entity.lua
-- GhostEntity(幽灵): real 在其他 cell 的投影。
-- real.outbox 应用到 ghost 自身 props / records / containers,
-- 下一 tick ghost 与 real 一样统一打包给观察者。

local Entity = require "tinyworld.entity.entity"

local GhostEntity = Entity.extend("GhostEntity")

function GhostEntity:getSpaceId()
    return self.space and self.space:getSpaceId()
end

function GhostEntity:ctor(def, id, kind, space, cell, realId, x, y)
    Entity.ctor(self, def, id, kind)
    self.isGhost = true
    self.isReal = false
    self.realId = realId
    self.space = space
    self.cell = cell
    self.props:set("x", x or 0)
    self.props:set("y", y or 0)
    self.realApp = nil
    self.realCellKey = nil
    self.pendingEvents = {}
end

-- Ghost -> Real RPC: ghost 持 realApp / realCellKey 直接定位真身
function GhostEntity:sendReal(method, data)
    if self.realApp == self.cell.host.appId then
        local cell = self.space:getCell(self.realCellKey)
        local real = cell and cell:get(self.realId)
        if real then
            if real[method] then
                real[method](real, data)
            else
                real:dispatchRealRpc(method, data)
            end
            return
        end
    else
        self.cell.host:send(self.realApp, "real_rpc",
            self:getSpaceId(), self.realCellKey, self.realId, method, data)
    end
end

function GhostEntity:callReal(method, data)
    if self.realApp == self.cell.host.appId then
        local cell = self.space:getCell(self.realCellKey)
        local real = cell and cell:get(self.realId)
        if real then
            if real[method] then
                return real[method](real, data)
            end
            return real:dispatchRealRpc(method, data)
        end
    end
    return self.cell.host:call(self.realApp, "real_rpc",
        self:getSpaceId(), self.realCellKey, self.realId, method, data)
end

-- real 跨 cell 迁移后, 旧 ghost 的 real 换到新的 app/cell
function GhostEntity:reparent(realApp, realCellKey)
    self.realApp = realApp
    self.realCellKey = realCellKey
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
        if op.type == "add" then cont:addFromData(op.data)
        elseif op.type == "remove" then cont:remove(op.id)
        elseif op.type == "set" then
            local child = cont:get(op.id)
            if child then
                for k, v in pairs(op.data or {}) do child[k] = v end
            end
        elseif op.type == "view" then
            for k, v in pairs(op.data or {}) do cont[k] = v end
        end
    end
end

return GhostEntity
