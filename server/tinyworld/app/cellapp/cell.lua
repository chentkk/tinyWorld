-- tinyworld/app/cellapp/cell.lua
-- 运行时 cell: 管理 cell 内 real / ghost 实体与网格 AOI。
-- 同步模型: 每个实体每 tick 把自身变更打包一次(outbox),
-- 然后以玩家(观察者)为视角, 从 visibleEntities 里取对应 outbox 发送。
-- 不再有 sendToAround / 每实体重复 AOI 查询。

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

function Cell:tick(dt)
    self:updateEntities(dt)
    self:updateVisibilities()
    self:buildOutboxes()
    self:deliverOutboxes()
end

function Cell:updateEntities(dt)
    for _, entity in pairs(self.entities) do
        if entity.isReal then entity:onTick(dt) end
    end
end

function Cell:updateVisibilities()
    for _, player in pairs(self.entities) do
        if player.isReal and player.kind == "Player" then
            self:updatePlayerVisibility(player)
        end
    end
end

-- 把一个 real 实体的本轮变更打入 outbox(只在这里 flush / collect 一次)
function Cell:buildRealOutbox(entity)
    local outbox = { events = {} }

    outbox.selfProps = entity:collectClientProps(true)
    outbox.aroundProps = entity:collectClientProps(false)

    outbox.recordOps = {}
    for name, rec in pairs(entity.records) do
        local ops = rec:flushSync()
        if ops and #ops > 0 then
            outbox.recordOps[name] = ops
        end
    end

    outbox.viewOps = {}
    for name, cont in pairs(entity.containers) do
        local ops = cont:flushSync()
        if ops and #ops > 0 then
            outbox.viewOps[name] = ops
        end
    end

    outbox.events = entity.pendingEvents
    entity.pendingEvents = {}
    entity:clearClientDirty()

    entity.outbox = outbox
end

function Cell:buildGhostOutbox(entity)
    local stage = entity:collectStage()
    local outbox = { aroundProps = stage, events = {} }
    entity.outbox = outbox
end

function Cell:buildOutboxes()
    for _, entity in pairs(self.entities) do
        if entity.isReal then
            self:buildRealOutbox(entity)
        elseif entity.isGhost then
            self:buildGhostOutbox(entity)
        end
    end
end

function Cell:sendProp(player, entity, props)
    if not props or not next(props) then return end

    local data = { t = "prop", n = "props", d = { entityId = entity.clientId or entity.id } }
    for k, v in pairs(props) do data.d[k] = v end
    self.app:sendToClient(player, data)
end

-- 以 player 为观察者, 取目标实体 outbox 中属于 around 的部分发送
function Cell:sendEntityAroundTo(player, entity)
    local outbox = entity.outbox
    if not outbox then return end

    if entity.isReal then
        self:sendProp(player, entity, outbox.aroundProps)
    elseif entity.isGhost then
        self:sendGhostViewProp(player, entity, outbox.aroundProps)
    end

    for name, ops in pairs(outbox.recordOps or {}) do
        self:sendRecordOps(player, entity, name, ops)
    end

    for name, ops in pairs(outbox.viewOps or {}) do
        self:sendViewOps(player, entity, name, ops)
    end

    for _, event in ipairs(outbox.events or {}) do
        self.app:sendToClient(player, event)
    end
end

-- ghost 的属性包不需要 seq, 数据直接放进 props message
function Cell:sendGhostViewProp(player, entity, stage)
    if not stage or not next(stage) then return end

    local data = { t = "prop", n = "props", d = { entityId = entity.clientId or entity.id } }
    for k, v in pairs(stage) do data.d[k] = v end
    self.app:sendToClient(player, data)
end

function Cell:sendRecordOps(player, entity, name, ops)
    self.app:sendToClient(player, { t = "record", n = name,
        d = { entityId = entity.clientId or entity.id, ops = ops } })
end

function Cell:sendViewOps(player, entity, name, ops)
    self.app:sendToClient(player, { t = "view", n = name,
        d = { entityId = entity.clientId or entity.id, ops = ops } })
end

function Cell:deliverOutboxes()
    for _, player in pairs(self.entities) do
        if player.isReal and player.kind == "Player" then
            self:deliverToPlayer(player)
        end
    end
end

function Cell:deliverToPlayer(player)
    player.visibleEntities = player.visibleEntities or {}

    -- 自己: 自身属性包 + 自己的战斗事件
    local selfOutbox = player.outbox
    if selfOutbox then
        if selfOutbox.selfProps and player.lastMoveSeq then
            selfOutbox.selfProps.seq = player.lastMoveSeq
        end
        self:sendProp(player, player, selfOutbox.selfProps)

        for _, event in ipairs(selfOutbox.events or {}) do
            self.app:sendToClient(player, event)
        end
    end

    -- 我看到的所有实体: 把它们的 around 包发给我
    for _, target in pairs(player.visibleEntities) do
        if target.outbox then
            self:sendEntityAroundTo(player, target)
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
            self.app:sendToClient(player, entities.objectAddMsg(other))
        end
    end

    for id, old in pairs(player.visibleEntities) do
        if not visible[id] then
            player.visibleEntities[id] = nil
            self.app:sendToClient(player, entities.objectRemoveMsg(old))
        end
    end
end

M.Cell = Cell
return M
