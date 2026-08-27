-- tinyworld/app/cellapp/cell.lua
-- 运行时 cell: 管理落入该 cell 的 real / ghost 实体、网格 AOI,
-- 并统一负责向周边玩家下发变更(属性 / 表格 / 视图 / 战斗事件)。
-- 每个实体每 tick 只做一次 AOI 查询, 下游复用同一份 around 列表。

local class = require "tinyworld.core.class"
local aoiMod = require "tinyworld.app.cellapp.aoi"
local entities = require "tinyworld.app.cellapp.entities"
local M = {}

local Cell = class.makeClass("Cell")

function Cell:ctor(cellInfo, app)
    self.info = cellInfo
    self.app = app
    self.entities = {}
    self.aoi = aoiMod.Aoi.new(app.spaceConfig.aoiRange, cellInfo.w, cellInfo.h)
    self.playerCount = 0
end

function Cell:key()
    return self.info.id
end

function Cell:addEntity(entity)
    if self.entities[entity.id] then return end

    entity.cell = self
    self.entities[entity.id] = entity
    self.aoi:enter(entity, entity.x, entity.y)
    if entity.kind == "Player" and entity.isReal then
        self.playerCount = self.playerCount + 1
    end
    entity:onEnterCell(self)
end

function Cell:removeEntity(entity)
    if not self.entities[entity.id] then return end

    self.entities[entity.id] = nil
    self.aoi:leave(entity, entity.x, entity.y)
    if entity.kind == "Player" and entity.isReal then
        self.playerCount = self.playerCount - 1
    end
    entity:onLeaveCell(self)
end

function Cell:get(id)
    return self.entities[id]
end

function Cell:queryRange(x, y)
    return self.aoi:query(x, y)
end

-- 战斗事件入口: 由底层同步组件调用, 不直接触碰 cell 内部结构
function Cell:postEvent(entity, data)
    entity.pendingEvents[#entity.pendingEvents + 1] = data
end

-- 一次 AOI 查询并过滤出周围 player, 供一次 tick 内多个 flush 复用
function Cell:queryAround(entity)
    local around = {}
    for _, other in ipairs(self.aoi:query(entity.x, entity.y)) do
        if other ~= entity and other.kind == "Player" and other.isReal and other.baseApp then
            around[#around + 1] = other
        end
    end
    return around
end

function Cell:sendToAround(around, data)
    for _, player in ipairs(around) do
        self.app:sendToClient(player, data)
    end
end

function Cell:sendToSelf(player, data)
    self.app:sendToClient(player, data)
end

-- 幽灵在下个 tick 把 real 同步来的变更发给周边
function Cell:flushGhostSync(ghost)
    local staged = ghost:collectStage()
    if not next(staged) then return end

    local data = { t = "prop", n = "props", d = { entityId = ghost.clientId } }
    for k, v in pairs(staged) do data.d[k] = v end
    self:sendToAround(self:queryAround(ghost), data)
end

-- 一个 real 实体的一轮全部下行: 属性 / 表格 / 视图 / 战斗事件
function Cell:flushRealSync(entity)
    local around = self:queryAround(entity)

    local props = entity:collectClientProps(false)
    if next(props) then
        local data = { t = "prop", n = "props", d = { entityId = entity.clientId } }
        for k, v in pairs(props) do data.d[k] = v end
        self:sendToAround(around, data)
    end

    for _, rec in pairs(entity.records) do
        local flush = rec:flushSync()
        if flush then
            self:sendToAround(around, { t = "record", n = flush.name,
                d = { entityId = entity.clientId, ops = flush.ops } })
        end
    end

    for _, cont in pairs(entity.containers) do
        local flush = cont:flushSync()
        if flush then
            self:sendToAround(around, { t = "view", n = flush.name,
                d = { entityId = entity.clientId, ops = flush.ops } })
        end
    end

    for _, event in ipairs(entity.pendingEvents) do
        self:sendToAround(around, event)
        if entity.kind == "Player" then
            self:sendToSelf(entity, event)
        end
    end
    entity.pendingEvents = {}
end

-- player 自身独占数据(如位置 reconciliation)单独下发
function Cell:flushSelfSync(player)
    local props = player:collectClientProps(true)
    if not next(props) then return end

    local data = { t = "prop", n = "props", d = { entityId = player.clientId } }
    for k, v in pairs(props) do data.d[k] = v end
    if player.lastMoveSeq then data.d.seq = player.lastMoveSeq end
    self:sendToSelf(player, data)
end

function Cell:tick(dt)
    self:updateEntities(dt)
    self:updatePlayerVisibilities()
    self:flushAll()
end

function Cell:updateEntities(dt)
    for _, entity in pairs(self.entities) do
        if entity.isReal then entity:onTick(dt) end
    end
end

function Cell:updatePlayerVisibilities()
    for _, player in pairs(self.entities) do
        if player.isReal and player.kind == "Player" then
            self:updatePlayerVisibility(player)
        end
    end
end

function Cell:flushAll()
    for _, entity in pairs(self.entities) do
        if entity.isReal then
            self:flushRealSync(entity)
            if entity.kind == "Player" then
                self:flushSelfSync(entity)
            end
            entity:clearClientDirty()
        elseif entity.isGhost then
            self:flushGhostSync(entity)
        end
    end
end

function Cell:updatePlayerVisibility(player)
    local visible = {}
    local range = self.app.spaceConfig.aoiRange

    for _, other in pairs(self.entities) do
        if other.id ~= player.id then
            local dx = other.x - player.x
            local dy = other.y - player.y
            if dx * dx + dy * dy <= range * range then
                visible[other.id] = other
            end
        end
    end

    player.visibleEntities = player.visibleEntities or {}

    for id, other in pairs(visible) do
        if player.visibleEntities[id] ~= other then
            player.visibleEntities[id] = other
            self:sendToSelf(player, entities.objectAddMsg(other))
        end
    end

    for id, old in pairs(player.visibleEntities) do
        if not visible[id] then
            player.visibleEntities[id] = nil
            self:sendToSelf(player, entities.objectRemoveMsg(old))
        end
    end
end

M.Cell = Cell
return M
