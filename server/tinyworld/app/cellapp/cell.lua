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
local SpatialIndex = require "tinyworld.app.cellapp.space.spatial_index"
local TimerScheduler = require "tinyworld.framework.timer.timer_scheduler"
local protocol = require "tinyworld.net.protocol"
local RealEntity = require "tinyworld.app.cellapp.entities.real_entity"
local GhostEntity = require "tinyworld.app.cellapp.entities.ghost_entity"
local defs = require "tinyworld.entity.defs"

-- 统一打包 ghost 创建请求
local function ghostReq(real)
    return {
        realId = real.id,
        kind = real.kind,
        x = real.x,
        y = real.y,
        ghostSnapshot = real:ghostSnapshot(),
    }
end

local Cell = class.makeClass("Cell")

function Cell:ctor(cellInfo, host, space)
    self.info = cellInfo
    self.host = host
    self.space = space
    self.entities = {}
    self.players = {}
    self.spatial = SpatialIndex.new(space.config.aoiRange, cellInfo.w, cellInfo.h)
    self.playerCount = 0

    -- entity 级定时器(时间轮, 一次性到期; 重复调度在 scheduler)
    self.timerScheduler = TimerScheduler.new()
end

function Cell:key()
    return self.info.id
end

-- entity 级定时器: delay 秒; times=-1 无限, 其他为总触发次数(缺省 1)。
function Cell:addTimer(entity, delay, times, fn)
    return self.timerScheduler:add(entity, delay, times, fn)
end

function Cell:removeTimer(id)
    return self.timerScheduler:remove(id)
end

function Cell:updateTimers(dt)
    return self.timerScheduler:update(dt)
end

function Cell:getSpaceId()
    return self.space and self.space:getSpaceId()
end

-- cell 是拥有 host(cellapp)/space 的运行时上下文,
-- 全局服务寻址(spawn etc.)统一由 Cell 完成, Entity 不直接访问 host。
function Cell:spawnEntity(kind, data, baseApp)
    assert(self.host and self.host.spawn_entity, "cell host has no spawn_entity")
    assert(self.space, "cell has no space")
    return self.host.spawn_entity(self:getSpaceId(), self:key(), kind, data, baseApp)
end

function Cell:spawnProjectile(kind, data)
    return self:spawnEntity(kind, data, nil)
end

function Cell:addEntity(entity)
    if self.entities[entity.id] then return end

    entity.cell = self
    self.entities[entity.id] = entity
    self.spatial:enter(entity, entity.x, entity.y)
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

    -- 实体离开本 cell 时, 框架负责清掉挂在本 cell 调度器上的定时器;
    -- 跨 cell 迁移后的新 cell 上由业务组件在 onMigrateIn 里重新添加。
    self.timerScheduler:clearEntity(entity:getRealId())

    self.entities[entity.id] = nil
    self.spatial:leave(entity, entity.x, entity.y)
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

function Cell:findByRealId(realId)
    return self.entities[realId]
end

function Cell:queryRange(x, y)
    return self.spatial:query(x, y)
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

    -- 时间轮定时器(秒转毫秒)
    self:updateTimers(dt)
end

function Cell:updateEntities(dt)
    for _, entity in pairs(self.entities) do
        if entity.isReal then entity:onTick(dt) end
    end
end

-- 实体 tick 后重算 AOI 网格, 保证 query 与实际位置一致
function Cell:syncAoi()
    for _, entity in pairs(self.entities) do
        self.spatial:move(entity, entity.x, entity.y)
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
            if cont.def.sync == "self" then outbox.selfViewOps[name] = flush.ops
            elseif cont.def.sync == "all" then outbox.viewOps[name] = flush.ops end
        end
    end

    entity.pendingEvents = {}
    entity:clearClientDirty()
    entity.outbox = outbox
    return outbox
end

function Cell:buildOutboxes()
    for _, entity in pairs(self.entities) do
        if entity:isNetworked() then
            self:buildOutbox(entity)
            if entity.isGhost and outboxHasChanges(entity.outbox) then
                self:ghostLog("ghost outbox ready real=%d ghost=%d",
                    entity.realId, entity.id)
            end
        end
    end
end

-- 把实体的一个属性包 append 到本站 tick 待发列表(不是立即发送)
function Cell:appendProp(msgs, entity, props)
    if not props or not next(props) then return end
    msgs[#msgs + 1] = protocol.propMsg(entity, props)
end

-- 以 player 为观察者, 取目标实体 outbox 中属于 around 的部分 append 到待发列表
function Cell:appendEntityAroundTo(msgs, entity)
    local outbox = entity.outbox
    if not outbox then return end

    -- real 与 ghost 的属性包都用 aroundProps; ghost 无需 seq, 直接进 props message
    self:appendProp(msgs, entity, outbox.aroundProps)

    for name, ops in pairs(outbox.recordOps or {}) do
        msgs[#msgs + 1] = protocol.recordMsg(entity:getRealId(), name, ops)
    end

    for name, ops in pairs(outbox.viewOps or {}) do
        msgs[#msgs + 1] = protocol.viewMsg(entity:getRealId(), name, ops)
    end

    for _, event in ipairs(outbox.events or {}) do
        msgs[#msgs + 1] = event
    end
end

function Cell:deliverOutboxes()
    for _, player in pairs(self.players) do
        self:deliverToPlayer(player)
    end
end

-- 收集本 tick 发给该玩家的全部消息, 合并成一份 batch 发给 baseapp,
-- 由 baseapp 一次编码/转发, 避免每个实体、每种消息各发一次。
function Cell:deliverToPlayer(player)
    player.visibleEntities = player.visibleEntities or {}
    local msgs = {}

    -- 自己: 自身属性包 + 自己的战斗事件
    -- (移动确认 seq 已作为 sync=self 的普通属性, 由 Move 组件 set 后自然进 selfProps;
    --  仅变化时才下发, 不会污染无关属性包)
    local selfOutbox = player.outbox
    if selfOutbox then
        self:appendProp(msgs, player, selfOutbox.selfProps)

        -- 自己也能看到自身 around views(如 modifiers_view)
        for name, ops in pairs(selfOutbox.viewOps or {}) do
            msgs[#msgs + 1] = protocol.viewMsg(player:getRealId(), name, ops)
        end
        for name, ops in pairs(selfOutbox.selfViewOps or {}) do
            msgs[#msgs + 1] = protocol.viewMsg(player:getRealId(), name, ops)
        end
        for _, event in ipairs(selfOutbox.events or {}) do
            msgs[#msgs + 1] = event
        end
    end

    -- 我看到的所有实体: 把它们的 around 包收集起来
    for _, target in pairs(player.visibleEntities) do
        if target.outbox then
            self:appendEntityAroundTo(msgs, target)
            self:ghostLog("deliver outbox player=%s source=%s entity=%d kind=%s",
                tostring(player.playerId), target.isGhost and "ghost" or "real",
                target:getRealId(), target.kind)
        end
    end

    if #msgs > 0 then
        self.host:sendToClient(player, protocol.batch(msgs))
    end
end

function Cell:updatePlayerVisibility(player)
    local visible = {}

    -- 使用十字链表索引做候选裁剪, 避免每 tick 对 cell 内全量对象做 O(N^2) 扫描。
    -- 非网络对象纯服务器可见, 不进玩家视野。
    for _, other in ipairs(self.spatial:query(player.x, player.y)) do
        if other.id ~= player.id and other:isNetworked() then
            visible[other.id] = other
        end
    end

    player.visibleEntities = player.visibleEntities or {}

    for id, other in pairs(visible) do
        if player.visibleEntities[id] ~= other then
            player.visibleEntities[id] = other
            self.host:sendToClient(player, protocol.objectAddMsg(other))
        end
    end

    for id, old in pairs(player.visibleEntities) do
        if not visible[id] then
            player.visibleEntities[id] = nil
            self.host:sendToClient(player, protocol.objectRemoveMsg(old))
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
        if real.isReal and real:canMigrate() and not real.__migrating then
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
        self:migrateLocal(real, target)
        return
    end

    self:migrateRemote(real, ideal)
end

-- 同 cellapp 本地迁移: 与跨 cellapp 迁移使用同一套 promoteGhost 语义。
-- ensureGhosts 可能已经提前在目标 cell 为 real 建好 ghost(二者共用 entity id),
-- 因此不能直接把 real 塞进 target; 统一消费 target 里的 ghost -> 提升为新 real。
-- 这样本地与远端迁移在对象身份 / ghost 清理 / witness 处理上完全一致。
function Cell:migrateLocal(real, target)
    real.__migrating = true

    -- 目标 cell 若还没有该 real 的 ghost, 先补一个(与 ensureGhostIn 语义一致)
    local ghost = target:findGhost(real.id)
    if not ghost then
        local key = real.id .. "@" .. target.info.id
        ghost = target:buildGhost(ghostReq(real))
        target:addEntity(ghost)
        real:addGhost({ key = key, app = self.host.appId, cellKey = target.info.id, sameApp = true })
    end

    local oldCell = real.cell
    real:onMigrateOut(oldCell)
    oldCell:removeEntity(real)
    oldCell:leaveWitness(real)

    local peers = self:collectGhostPeers(real)
    self:reparentOldGhosts(real, target.info, peers)

    -- 与跨 app ghost_promote 完全相同的提升入口
    local promoted = target:promoteGhost(real.id, {
        fromApp = self.host.appId,
        witnessCellKey = oldCell:key(),
        peers = peers,
        baseApp = real.baseApp,
        playerId = real.playerId,
        lastMigrateTime = real.lastMigrateTime,
        snapshot = real:snapshot(), -- 完整迁移快照(props/records/containers)
    })
    if not promoted then
        real.__migrating = false
        return
    end

    -- 迁移完成通知(组件在此重新添加自己的 cell 级定时器等)
    promoted:onMigrateIn(target)

    -- 本地迁移虽然 app 不变, 但 cellKey 已变, 必须通知 baseapp 更新绑定,
    -- 否则后续客户端指令仍会打到旧 cell 导致 "entity not found"。
    if promoted.baseApp then
        self.host:sendService(promoted.baseApp, "rebind_cell",
            promoted.playerId, self:getSpaceId(), target.info.id, self.host:selfAddr())
    end

    real.__migrating = false
end

function Cell:migrateRemote(real, ideal)
    real.__migrating = true
    local snapshot = real:snapshot()

    local ok = self.host:call(ideal.appId, "ghost_create", self:getSpaceId(), ideal.id, {
        realId = real.id, kind = real.kind, x = real.x, y = real.y,
        ghostSnapshot = real:ghostSnapshot(), fromApp = self.host.appId,
        ownerCellKey = self.info.id, promote = true,
    })
    if not ok then
        real.__migrating = false
        return
    end

    local oldCell = real.cell
    real:onMigrateOut(oldCell)
    oldCell:removeEntity(real)
    oldCell:leaveWitness(real)

    local peers = self:collectGhostPeers(real)
    self:reparentOldGhosts(real, ideal, peers)
    self.host:send(ideal.appId, "ghost_promote", self:getSpaceId(), ideal.id, real.id, {
        fromApp = self.host.appId,
        witnessCellKey = oldCell:key(),
        peers = peers,
        baseApp = real.baseApp,
        playerId = real.playerId,
        lastMigrateTime = real.lastMigrateTime,
        snapshot = snapshot,
    })
    real.__migrating = nil
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
            self.host:send(peer.app, "ghost_reparent", self:getSpaceId(),
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

-- 为 neighbor cell 维护 real 的 ghost。
-- ghost 是否创建只看 canGhost(默认 true), 与是否可迁移(canMigrate)无关:
-- 短生命周期的 projectile 不迁移, 但仍要在这里同步出 ghost。
function Cell:ghostLog(fmt, ...)
    log.info("[ghost][cell " .. tostring(self.info and self.info.id) .. "] " .. fmt, ...)
end

function Cell:ensureGhosts()
    for _, real in pairs(self.entities) do
        if real.isReal and real:canGhost() and not real.__migrating then
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
        self.host:send(info.app, "ghost_destroy", self:getSpaceId(), info.cellKey, real.id)
        self:ghostLog("request destroy remote ghost real=%d app=%d cell=%s",
            real.id, info.app, info.cellKey)
    end
    real.ghosts[key] = nil
end

-- real 生命周期结束(销毁)时清理其所有 ghost。
-- 迁移路径走 reparent, 不经过 destroy; 因此这里可以无条件清空。
function Cell:destroyGhostsOf(real)
    for _, info in pairs(real.ghosts or {}) do
        self:destroyGhost(real, real.id .. "@" .. info.cellKey, info)
    end
end

function Cell:ensureGhostIn(real, neighborInfo)
    local key = real.id .. "@" .. neighborInfo.id
    if real.ghosts[key] then return end

    if neighborInfo.appId == self.host.appId then
        local target = self.space:getCell(neighborInfo.id)
        if not target then return end

        local ghost = target:buildGhost(ghostReq(real))
        ghost.realApp = self.host.appId
        ghost.realCellKey = self.info.id
        target:addEntity(ghost)
        real:addGhost({ key = key, app = self.host.appId, cellKey = neighborInfo.id, sameApp = true })
        self:ghostLog("create local ghost real=%d cell=%s ghostId=%d",
            real.id, neighborInfo.id, ghost.id)
        return
    end

    local ok = self.host:call(neighborInfo.appId, "ghost_create", self:getSpaceId(), neighborInfo.id, {
        realId = real.id, kind = real.kind, x = real.x, y = real.y,
        ghostSnapshot = real:ghostSnapshot(), fromApp = self.host.appId,
        ownerCellKey = self.info.id, promote = false,
    })
    if ok then
        real:addGhost({ key = key, app = neighborInfo.appId, cellKey = neighborInfo.id })
        self:ghostLog("create remote ghost real=%d app=%d cell=%s", real.id, neighborInfo.appId, neighborInfo.id)
    end
end

-- 统一 ghost 创建入口: 接收打包好的 ghost 请求(realId/kind/x/y/ghostSnapshot),
-- 本地与远端 cellapp 最终都调用同一个方法。
function Cell:buildGhost(req)
    local def = defs.get(req.kind)
    if not def then return nil end

    local ghost = GhostEntity.new(def, req.realId, req.kind, self.space, self, req.realId, req.x, req.y)
    ghost:restore(req.ghostSnapshot)
    ghost.props:collectSync() -- 初始属性随 object add 下发, 不再作为变更重复广播
    return ghost
end

-- 本 cell 内查找某 real 的 ghost
function Cell:findGhost(realId)
    local entity = self.entities[realId]
    if entity and entity.isGhost then return entity end
    return nil
end

-- 本 cell 内留下 witness ghost(同 app 迁移用)
function Cell:leaveWitness(real)
    local witness = self:buildGhost(ghostReq(real))
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

    ghost = self:buildGhost(req)
    if not ghost then return false end

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
    -- 迁移快照必须存在, 否则说明迁移请求缺少完整状态
    assert(req.snapshot, "promoteGhost: snapshot required")
    real:restore(req.snapshot)
    real.baseApp = req.baseApp
    real.playerId = req.playerId
    real.lastMigrateTime = req.lastMigrateTime or real.lastMigrateTime

    real.ghosts = {}
    for _, peer in ipairs(req.peers or {}) do
        real:addGhost({ app = peer.app, cellKey = peer.cellKey, sameApp = peer.sameApp })
    end
    if req.witnessCellKey then
        real:addGhost({ app = req.fromApp, cellKey = req.witnessCellKey, witness = true })
    end

    self:removeEntity(ghost)
    self:addEntity(real)

    -- 迁移构建流程与 spawn 一致: 数据恢复后装配组件并触发 onCreate,
    -- 组件在 onCreate 里重新注册 rpc / 初始化状态(新实例, 必须重跑);
    -- 迁移完成回调 onMigrateIn 由调用者在返回后触发。
    real:openViews(real.def.cellOpenViews)
    real:setupComponents(real.def.cellComponents)
    real:setReady()
    real:onCreate()

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
