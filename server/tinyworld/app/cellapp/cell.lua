-- tinyworld/app/cellapp/cell.lua
-- 运行时 cell: 管理 cell 内 real / ghost 实体与网格 AOI。
-- 同步模型: 每个实体每 tick 把自身变更打包一次(outbox),
-- 然后以玩家(观察者)为视角, 从 visibleEntities 里取对应 outbox 发送。
-- 不再有 sendToAround / 每实体重复 AOI 查询。

local class = require "tinyworld.core.class"
local log = require "tinyworld.core.log"

local function outboxHasChanges(outbox)
    outbox = outbox or {}
    return next(outbox.selfProps or {}) ~= nil or next(outbox.aroundProps or {}) ~= nil or
           next(outbox.recordOps or {}) ~= nil or next(outbox.viewOps or {}) ~= nil or
           #(outbox.events or {}) > 0
end
local aoiMod = require "tinyworld.app.cellapp.aoi"
local entityMsg = require "tinyworld.app.cellapp.entity_msg"
local RealEntity = require "tinyworld.app.cellapp.real_entity"
local GhostEntity = require "tinyworld.app.cellapp.ghost_entity"
local defs = require "tinyworld.entity.defs"

local Cell = class.makeClass("Cell")

function Cell:ctor(cellInfo, host, space)
    self.info = cellInfo
    self.host = host
    self.space = space
    self.entities = {}
    self.players = {}
    self.aoi = aoiMod.new(space.config.aoiRange, cellInfo.w, cellInfo.h)
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
    -- object add 已携带全量 props, 避免同 tick 再发增量 prop
    entity:clearClientDirty()
    if entity.kind == "Player" and entity.isReal then
        self.playerCount = self.playerCount + 1
    end
    if entity.kind == "Player" and entity.isReal then
        self.players[entity.id] = entity
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
    if entity.kind == "Player" and entity.isReal then
        self.players[entity.id] = nil
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
    self:syncAoi()
    self:updateVisibilities()
    self:buildOutboxes()
    self:deliverOutboxes()

    -- 同步之后做 cell 内部维护, 避免和上面的遍历互相影响
    self:checkMigrations()
    self:ensureGhosts()
    self:broadcastGhostChanges()
end

function Cell:updateEntities(dt)
    for _, entity in pairs(self.entities) do
        if entity.isReal then entity:onTick(dt) end
    end
end

-- 实体 tick 后重算 AOI 网格, 保证 query 与实际位置一致
function Cell:syncAoi()
    for _, entity in pairs(self.entities) do
        self.aoi:move(entity, entity.x, entity.y)
    end
end

function Cell:updateVisibilities()
    for _, player in pairs(self.players) do
        self:updatePlayerVisibility(player)
    end
end

-- 把实体的本轮变更打成 outbox。Real 与 Ghost 共用:
-- real 的变更是 tick 产生的, ghost 的变更是 real.outbox 应用来的。
function Cell:buildOutbox(entity)
    local outbox = {
        selfProps = entity:collectClientProps(true),
        aroundProps = entity:collectClientProps(false),
        recordOps = {},
        viewOps = {},
        selfViewOps = {},
        events = entity.pendingEvents,
    }

    for name, rec in pairs(entity.records) do
        local flush = rec:flushSync()
        if flush and #flush.ops > 0 then outbox.recordOps[name] = flush.ops end
    end

    for name, cont in pairs(entity.containers) do
        local flush = cont:flushSync()
        if flush and #flush.ops > 0 then
            if cont.def.selfOnly then outbox.selfViewOps[name] = flush.ops
            else outbox.viewOps[name] = flush.ops end
        end
    end

    entity.pendingEvents = {}
    entity:clearClientDirty()
    entity.outbox = outbox
    return outbox
end

function Cell:buildOutboxes()
    for _, entity in pairs(self.entities) do
        self:buildOutbox(entity)
        if entity.isGhost and outboxHasChanges(entity.outbox) then
            self:ghostLog("ghost outbox ready real=%d ghost=%d",
                entity.realId, entity.id)
        end
    end
end

function Cell:sendProp(player, entity, props)
    if not props or not next(props) then return end

    local data = { t = "prop", n = "props", d = { entityId = entity.clientId or entity.id } }
    for k, v in pairs(props) do data.d[k] = v end
    self.host:sendToClient(player, data)
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
        self.host:sendToClient(player, event)
    end
end

-- ghost 的属性包不需要 seq, 数据直接放进 props message
function Cell:sendGhostViewProp(player, entity, stage)
    if not stage or not next(stage) then return end

    local data = { t = "prop", n = "props", d = { entityId = entity.clientId or entity.id } }
    for k, v in pairs(stage) do data.d[k] = v end
    self.host:sendToClient(player, data)
end

function Cell:sendRecordOps(player, entity, name, ops)
    self.host:sendToClient(player, { t = "record", n = name,
        d = { entityId = entity.clientId or entity.id, ops = ops } })
end

function Cell:sendViewOps(player, entity, name, ops)
    self.host:sendToClient(player, { t = "view", n = name,
        d = { entityId = entity.clientId or entity.id, ops = ops } })
end

function Cell:deliverOutboxes()
    for _, player in pairs(self.players) do
        self:deliverToPlayer(player)
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

        -- 自己也能看到自身 around views(如 modifiers_view)
        for name, ops in pairs(selfOutbox.viewOps or {}) do
            self:sendViewOps(player, player, name, ops)
        end
        for name, ops in pairs(selfOutbox.selfViewOps or {}) do
            self:sendViewOps(player, player, name, ops)
        end
        for _, event in ipairs(selfOutbox.events or {}) do
            self.host:sendToClient(player, event)
        end
    end

    -- 我看到的所有实体: 把它们的 around 包发给我
    for _, target in pairs(player.visibleEntities) do
        if target.outbox then
            self:sendEntityAroundTo(player, target)
            self:ghostLog("deliver outbox player=%s source=%s entity=%d kind=%s",
                tostring(player.playerId), target.isGhost and "ghost" or "real",
                target.clientId or target.id, target.kind)
        end
    end
end

function Cell:updatePlayerVisibility(player)
    local visible = {}
    local range = self.space.config.aoiRange

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
            self.host:sendToClient(player, entityMsg.objectAddMsg(other))
        end
    end

    for id, old in pairs(player.visibleEntities) do
        if not visible[id] then
            player.visibleEntities[id] = nil
            self.host:sendToClient(player, entityMsg.objectRemoveMsg(old))
        end
    end
end

-- cell 内部维护: 检查本 cell 中的 real 是否该跨 cell
-- 迁移策略: 目标 cell 与抑制参数都在 Cell 内部处理
function Cell:shouldMigrate(real, ideal)
    local cfg = self.space.config
    if real.x - ideal.x < cfg.hysteresis then return false end
    if ideal.x + ideal.w - real.x < cfg.hysteresis then return false end
    if real.y - ideal.y < cfg.hysteresis then return false end
    if ideal.y + ideal.h - real.y < cfg.hysteresis then return false end

    return self.host:now() - real.lastMigrateTime >= cfg.minMigrateInterval
end

function Cell:checkMigrations()
    local toMigrate = {}
    for _, real in pairs(self.entities) do
        if real.isReal and not real.migrating then
            local ideal = self.space.config:cellAt(real.x, real.y)
            if ideal.id ~= self.info.id and self:shouldMigrate(real, ideal) then
                toMigrate[#toMigrate + 1] = { real = real, ideal = ideal }
            end
        end
    end

    for _, item in ipairs(toMigrate) do
        self:migrateEntity(item.real, item.ideal)
    end
end

-- 目标 cell 在本 cellapp: 直接换 cell 并留 witness
-- 目标 cell 在别的 cellapp: 走远端迁移协议(消息边界仍是 app 收发)
function Cell:migrateEntity(real, ideal)
    real.lastMigrateTime = self.host:now()

    local target = self.space:getCell(ideal.id)
    if target then
        real.cell:leaveWitness(real)
        real.cell:removeEntity(real)
        real.cell = target
        target:addEntity(real)
        return
    end

    self:migrateRemote(real, ideal)
end

function Cell:migrateRemote(real, ideal)
    real.migrating = true
    local snapshot = real:ghostSnapshot()

    local ok = self.host:call(ideal.appId, "ghost_create", self.space.spaceId, ideal.id, {
        realId = real.id, kind = real.kind, x = real.x, y = real.y,
        snapshot = snapshot, fromApp = self.host.appId,
        ownerCellKey = self.info.id, promote = true,
    })
    if not ok then
        real.migrating = false
        return
    end

    real.cell:leaveWitness(real)
    real.cell:removeEntity(real)

    local peers = self:collectGhostPeers(real)
    self:reparentOldGhosts(real, ideal, peers)
    self.host:send(ideal.appId, "ghost_promote", self.space.spaceId, ideal.id, real.id, {
        fromApp = self.host.appId,
        witnessCellKey = real.cell.info.id,
        peers = peers,
        baseApp = real.baseApp,
        playerId = real.playerId,
        initData = real.cellInitData,
    })
    real.migrating = nil
end

-- 迁移前显式通知所有旧 ghost: real 换到新的 app/cell
function Cell:reparentOldGhosts(real, ideal, peers)
    for _, peer in ipairs(peers) do
        if peer.app == self.host.appId then
            local cell = self.space:getCell(peer.cellKey)
            local ghost = cell and cell:findGhost(real.id)
            if ghost then
                ghost:reparent(ideal.appId, ideal.id)
                self:ghostLog("reparent local ghost real=%d ghost=%d -> app=%d cell=%s",
                    real.id, ghost.id, ideal.appId, ideal.id)
            end
        else
            self.host:send(peer.app, "ghost_reparent", self.space.spaceId,
                peer.cellKey, real.id, ideal.appId, ideal.id)
            self:ghostLog("request reparent ghost real=%d app=%d cell=%s -> app=%d cell=%s",
                real.id, peer.app, peer.cellKey, ideal.appId, ideal.id)
        end
    end
end

function Cell:collectGhostPeers(real)
    local peers = {}
    for _, info in pairs(real.ghosts) do
        local ghostId
        if info.app == self.host.appId then
            local cell = self.space:getCell(info.cellKey)
            local ghost = cell and cell:findGhost(real.id)
            ghostId = ghost and ghost.id
        end
        peers[#peers + 1] = {
            app = info.app, cellKey = info.cellKey, sameApp = info.sameApp,
            ghostId = ghostId,
        }
    end
    return peers
end

-- 为 neighbor cell 有玩家的地方维护 real 的 ghost
function Cell:ghostLog(fmt, ...)
    log.info("[ghost][cell " .. tostring(self.info and self.info.id) .. "] " .. fmt, ...)
end

function Cell:ensureGhosts()
    for _, real in pairs(self.entities) do
        if real.isReal and not real.migrating then
            self:pruneGhosts(real)

            for _, neighbor in ipairs(self.space.config:neighbors(self.info)) do
                if neighbor.id ~= self.info.id and neighbor:ghostContains(real.x, real.y) then
                    self:ensureGhostIn(real, neighbor)
                end
            end
        end
    end
end

-- 实体移出某 cell 的 ghost_rect -> 销毁那里的 ghost
function Cell:pruneGhosts(real)
    for key, info in pairs(real.ghosts) do
        local cellInfo = self.space.config.byCellId[info.cellKey]
        if cellInfo and not cellInfo:ghostContains(real.x, real.y) then
            self:destroyGhost(real, key, info)
        end
    end
end

function Cell:destroyGhost(real, key, info)
    if info.app == self.host.appId then
        local cell = self.space:getCell(info.cellKey)
        local ghost = cell and cell:findGhost(real.id)
        if ghost then
            cell:removeEntity(ghost)
            self:ghostLog("destroy local ghost real=%d cell=%s", real.id, info.cellKey)
        end
    else
        self.host:send(info.app, "ghost_destroy", self.space.spaceId, info.cellKey, real.id)
        self:ghostLog("request destroy remote ghost real=%d app=%d cell=%s",
            real.id, info.app, info.cellKey)
    end
    real.ghosts[key] = nil
end

function Cell:ensureGhostIn(real, neighborInfo)
    local key = real.id .. "@" .. neighborInfo.id
    if real.ghosts[key] then return end

    if neighborInfo.appId == self.host.appId then
        local target = self.space:getCell(neighborInfo.id)
        if not target then return end

        local ghost = target:buildGhost(real)
        ghost.realApp = self.host.appId
        ghost.realCellKey = self.info.id
        target:addEntity(ghost)
        real:addGhost({ key = key, app = self.host.appId, cellKey = neighborInfo.id, sameApp = true })
        self:ghostLog("create local ghost real=%d cell=%s ghostId=%d",
            real.id, neighborInfo.id, ghost.id)
        return
    end

    local ok = self.host:call(neighborInfo.appId, "ghost_create", self.space.spaceId, neighborInfo.id, {
        realId = real.id, kind = real.kind, x = real.x, y = real.y,
        snapshot = real:ghostSnapshot(), fromApp = self.host.appId,
        ownerCellKey = self.info.id, promote = false,
    })
    if ok then
        real:addGhost({ key = key, app = neighborInfo.appId, cellKey = neighborInfo.id })
        self:ghostLog("create remote ghost real=%d app=%d cell=%s", real.id, neighborInfo.appId, neighborInfo.id)
    end
end

-- 在本 cell 构造一个 real 的 ghost
function Cell:buildGhost(real)
    local def = defs.get(real.kind) or real.def
    local ghost = GhostEntity.new(def, self.host:nextId(), real.kind, self.space, self, real.id, real.x, real.y)
    ghost.props:load(real.props:dump())
    ghost.props:collectSync() -- 初始属性随 object add 下发, 不再作为变更重复广播
    return ghost
end

-- 本 cell 内查找某 real 的 ghost
function Cell:findGhost(realId)
    for _, entity in pairs(self.entities) do
        if entity.isGhost and entity.realId == realId then return entity end
    end
    return nil
end

-- 本 cell 内留下 witness ghost(同 app 迁移用)
function Cell:leaveWitness(real)
    local witness = self:buildGhost(real)
    witness.realApp = self.host.appId
    self:addEntity(witness)
    real:addGhost({ key = real.id .. "@" .. self.info.id, app = self.host.appId,
        cellKey = self.info.id, sameApp = true })
    real.witnessCellKey = self.info.id
    self:ghostLog("create witness ghost real=%d cell=%s ghostId=%d",
        real.id, self.info.id, witness.id)
end

-- 把本 cell 内 real 的 ghost 脏属性广播出去
function Cell:broadcastGhostChanges()
    for _, real in pairs(self.entities) do
        if real.isReal and real.outbox and outboxHasChanges(real.outbox) then
            local count = 0
            for _ in pairs(real.ghosts) do count = count + 1 end
            if count > 0 then
                self:ghostLog("real outbox sync real=%d ghosts=%d x=%.1f",
                    real.id, count, real.x)
            end
            real:sendGhostEach(real.outbox)
            real.outbox = nil
        end
    end
end

-- 远端请求在本 cell 创建 ghost
function Cell:upsertRemoteGhost(req)
    local ghost = self:findGhost(req.realId)
    if ghost then return true end

    local def = defs.get(req.kind)
    if not def then return false end

    ghost = GhostEntity.new(def, self.host:nextId(), req.kind, self.space, self, req.realId, req.x, req.y)
    if req.snapshot and req.snapshot.props then
        ghost.props:load(req.snapshot.props)
    end
    ghost.realApp = req.fromApp
    ghost.realCellKey = req.ownerCellKey
    ghost.promote = req.promote

    self:addEntity(ghost)
    return true
end

-- 远端迁移终点: 本 cell 中的 ghost 提升为 real
function Cell:promoteGhost(realId, req)
    local ghost = self:findGhost(realId)
    if not ghost then return false end
    self:ghostLog("destroy ghost(consumed by migration) real=%d ghostId=%d",
        realId, ghost.id)

    local real = RealEntity.new(ghost.def, realId, ghost.kind, self.space, self, ghost.x, ghost.y)
    real.props:load(ghost.props:dump())
    real.baseApp = req.baseApp
    real.playerId = req.playerId
    real.cellInitData = req.initData

    real.ghosts = {}
    for _, peer in ipairs(req.peers or {}) do
        real:addGhost({ app = peer.app, cellKey = peer.cellKey, sameApp = peer.sameApp })
    end
    if req.witnessCellKey then
        real:addGhost({ app = req.fromApp, cellKey = req.witnessCellKey, witness = true })
    end

    self:removeEntity(ghost)
    self:addEntity(real)
    self:ghostLog("promote real=%d cell=%s", real.id, self.info.id)
    self.host:notifyEntityMoved(real)
    return real
end

function Cell:applyRemoteGhostSync(realId, outbox)
    local ghost = self:findGhost(realId)
    if ghost then
        ghost:applyOutbox(outbox)
        self:ghostLog("remote ghost apply outbox real=%d ghost=%d", realId, ghost.id)
    end
end

function Cell:destroyRemoteGhost(realId)
    local ghost = self:findGhost(realId)
    if ghost then self:removeEntity(ghost) end
end

return Cell
