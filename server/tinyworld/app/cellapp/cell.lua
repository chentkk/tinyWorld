-- tinyworld/space/cell.lua
-- 运行时 cell: 管理落在该 cell 的 real / ghost 实体, 网格 AOI,
-- 并负责向周围玩家下发属性 / 表格 / 视图变更。

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
    self.battleEvents = {}
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

-- 发给实体周围的所有 player 客户端
function Cell:sendToAround(entity, msg)
    local around = self.aoi:query(entity.x, entity.y)
    for _, other in ipairs(around) do
        if other ~= entity and other.kind == "Player" and other.isReal and other.baseApp then
            self.app:sendToClient(other, msg)
        end
    end
end

-- ghost 实体同步给周围玩家(下一个 tick 由 cell 调用)
function Cell:flushSelfSync(player)
    local props = player:collectClientProps(true)
    if not next(props) then return end
    local msg = { t = "prop", n = "props", d = { entityId = player.clientId } }
    for k, v in pairs(props) do msg.d[k] = v end
    if player.lastMoveSeq then msg.d.seq = player.lastMoveSeq end
    self.app:sendToClient(player, msg)
end

function Cell:flushEntitySync(entity, dt)
    if entity.isGhost then
        local staged = entity:collectStage()
        if next(staged) then
            local msg = { t = "prop", n = "props", d = { entityId = entity.clientId } }
            for k, v in pairs(staged) do msg.d[k] = v end
            self:sendToAround(entity, msg)
        end
        return
    end

    -- real: 属性(同步给周围其他玩家, 自身已单独处理)
    local props = entity:collectClientProps(false)
    if next(props) then
        local msg = { t = "prop", n = "props", d = { entityId = entity.clientId } }
        for k, v in pairs(props) do msg.d[k] = v end
        self:sendToAround(entity, msg)
    end

    -- 表格
    for _, rec in pairs(entity.records) do
        local flush = rec:flushSync()
        if flush then
            self:sendToAround(entity, { t = "record", n = flush.name,
                d = { entityId = entity.clientId, ops = flush.ops } })
        end
    end

    -- 视图(容器)
    for _, cont in pairs(entity.containers) do
        local flush = cont:flushSync()
        if flush then
            self:sendToAround(entity, { t = "view", n = flush.name,
                d = { entityId = entity.clientId, ops = flush.ops } })
        end
    end
end

function Cell:tick(dt)
    -- 1. 实体逻辑
    for _, entity in pairs(self.entities) do
        if entity.isReal then
            entity:onTick(dt)
        end
    end

    -- 2. 玩家视野维护(先简单基于网格)
    for _, player in pairs(self.entities) do
        if player.isReal and player.kind == "Player" then
            self:updatePlayerVisibility(player)
        end
    end

    -- 3. 同步冲刷: 先给周围(others), 再给自身(self), 最后清脏
    for _, entity in pairs(self.entities) do
        if entity.isReal then
            self:flushEntitySync(entity, dt)
            if entity.kind == "Player" then
                self:flushSelfSync(entity)
            end
            entity:clearClientDirty()
        end
    end

    -- 4. 战斗一次性事件最后冲刷, 保证在 entity add / prop 之后
    self:flushBattleEvents()
end

function Cell:flushBattleEvents()
    local events = self.battleEvents
    self.battleEvents = {}

    for _, event in ipairs(events) do
        local origin = event.origin
        if origin.kind == "Player" and origin.isReal and origin.baseApp then
            self.app:sendToClient(origin, event.msg)
        end
        self:sendToAround(origin, event.msg)
    end
end

function Cell:updatePlayerVisibility(player)
    local around = {}
    for _, other in pairs(self.entities) do
        if other.id ~= player.id then
            around[#around + 1] = other
        end
    end

    -- 过滤距离
    local visible = {}
    local range = self.app.spaceConfig.aoiRange
    for _, other in ipairs(around) do
        local dx = other.x - player.x
        local dy = other.y - player.y
        if dx * dx + dy * dy <= range * range then
            visible[other.clientId] = other
        end
    end

    -- 进入视野
    for clientId, other in pairs(visible) do
        if not player.visibleList[clientId] then
            player.visibleList[clientId] = true
            self.app:sendToClient(player, entities.objectAddMsg(other))
        end
    end

    -- 离开视野
    for clientId in pairs(player.visibleList) do
        if not visible[clientId] then
            player.visibleList[clientId] = nil
            self.app:sendToClient(player, { t = "object", n = "remove", d = { entityId = clientId } })
        end
    end
end

M.Cell = Cell
return M
