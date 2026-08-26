-- tinyworld/space/local_space.lua
-- 局部的 space 对象: 管理该 cellapp 上运行的 cell。
-- 职责: 本地 cell tick、real-ghost 属性同步、实体跨 cell / 跨 cellapp 迁移,
-- 以及迁移抖动抑制(穿透阈值 + 最小迁移间隔)。

local class = require "tinyworld.core.class"
local cellMod = require "tinyworld.app.cellapp.cell"
local entities = require "tinyworld.app.cellapp.entities"
local defs = require "tinyworld.entity.defs"
local M = {}

local LocalSpace = class.makeClass("LocalSpace")

function LocalSpace:ctor(app)
    self.app = app
    self.config = app.spaceConfig
    self.cells = {} -- local cell 对象
    self.byKey = {}
    self.spaceId = app.spaceConfig.id
end

function LocalSpace:addLocalCell(cellInfo)
    local cell = cellMod.Cell.new(cellInfo, self.app)
    self.cells[#self.cells + 1] = cell
    self.byKey[cellInfo.id] = cell
    return cell
end

function LocalSpace:getCell(key)
    return self.byKey[key]
end

function LocalSpace:isLocal(key)
    return self.byKey[key] ~= nil
end

function LocalSpace:tick(dt)
    for _, cell in ipairs(self.cells) do
        cell:tick(dt)
    end

    -- 迁移与 ghost 维护放在 tick 尾部, 避免遍历中修改 cell
    for _, cell in ipairs(self.cells) do
        for _, entity in pairs(cell.entities) do
            if entity.isReal then
                local dirty = entity:collectGhostDirty()
                if next(dirty) then
                    self:broadcastGhost(entity, dirty)
                end
                self:maintainEntityCells(entity)
            end
        end
    end
end

-- 迁移判断 + 周边 ghost 维护
function LocalSpace:maintainEntityCells(real)
    if real.migrating then return end

    local ideal = self.config:cellAt(real.x, real.y)
    local current = real.cell.info

    if ideal.id ~= current.id then
        if self:shouldMigrate(real, ideal) then
            self:migrateEntity(real, ideal)
            return
        end
    end

    self:ensureGhosts(real)
end

-- 抗抖动: 必须深入目标 cell 超过阈值, 且满足最小迁移间隔
function LocalSpace:shouldMigrate(real, ideal)
    local info = ideal
    if real.x - info.x < self.config.hysteresis then return false end
    if info.x + info.w - real.x < self.config.hysteresis then return false end
    if real.y - info.y < self.config.hysteresis then return false end
    if info.y + info.h - real.y < self.config.hysteresis then return false end

    if self.app:now() - real.lastMigrateTime < self.config.minMigrateInterval then
        return false
    end
    return true
end

function LocalSpace:migrateEntity(real, ideal)
    real.lastMigrateTime = self.app:now()

    if self.byKey[ideal.id] and self.byKey[real.cell.info.id] then
        -- 同 app 迁移: 旧 cell 留见证 ghost
        local oldCellKey = real.cell.info.id
        self:leaveGhostWitness(real, oldCellKey)
        real.cell:removeEntity(real)
        local target = self.byKey[ideal.id]
        real.cell = target
        target:addEntity(real)
        return
    end

    self:startRemoteMigration(real, ideal)
end

-- 同 app: 旧 cell 生成见证 ghost, 新位置继续当 real
function LocalSpace:leaveGhostWitness(real, oldCellKey)
    local oldCell = self.byKey[oldCellKey]
    if not oldCell then return end

    local witness = self:buildGhost(real, oldCell, real.x, real.y)
    witness.realApp = self.app.appId
    oldCell:addEntity(witness)
    real:addGhost({ key = real.id .. "@" .. oldCellKey, app = self.app.appId, cellKey = oldCellKey, sameApp = true })
    real.witnessCellKey = oldCellKey
end

-- 跨 app 迁移: 先在目标 app 建立 ghost, 再降级为 witness, 最后提升
function LocalSpace:startRemoteMigration(real, ideal)
    real.migrating = true
    local targetApp = ideal.appId
    local snapshot = real:ghostSnapshot()

    local ok = self.app:call(targetApp, "ghost_create", self.spaceId, ideal.id, {
        realId = real.id, kind = real.kind, x = real.x, y = real.y,
        snapshot = snapshot, fromApp = self.app.appId,
        ownerCellKey = real.cell.info.id, promote = true,
    })

    if not ok then
        real.migrating = false
        return
    end

    self:leaveGhostWitness(real, real.cell.info.id)
    real.cell:removeEntity(real)

    local peers = self:collectGhostPeers(real)
    self.app:send(targetApp, "ghost_promote", self.spaceId, ideal.id, real.id, {
        fromApp = self.app.appId,
        witnessCellKey = real.cell.info.id,
        peers = peers,
    })
    real.migrating = nil
end

function LocalSpace:collectGhostPeers(real)
    local peers = {}
    for _, info in pairs(real.ghosts) do
        peers[#peers + 1] = { app = info.app, cellKey = info.cellKey, sameApp = info.sameApp }
    end
    return peers
end

-- 确保 real 在周围有玩家的邻居 cell 中拥有 ghost
function LocalSpace:ensureGhosts(real)
    local ideal = self.config:cellAt(real.x, real.y)
    for _, neighbor in ipairs(self.config:neighbors(real.cell.info)) do
        if neighbor.id == ideal.id and self.byKey[ideal.id] then
            -- 本 app 内的理想 cell 不需要 ghost(直接迁移)
        elseif self:neighborNeedsGhost(neighbor) then
            self:ensureGhostIn(real, neighbor)
        end
    end
end

function LocalSpace:neighborNeedsGhost(neighborInfo)
    if neighborInfo.appId == self.app.appId then
        local cell = self.byKey[neighborInfo.id]
        if not cell then return false end
        return cell.playerCount > 0
    end

    -- 远端 cell 是否有玩家由远端维护: 保守地请求, 远端自行判断
    return true
end

function LocalSpace:ensureGhostIn(real, neighborInfo)
    local key = real.id .. "@" .. neighborInfo.id
    if real.ghosts[key] then return end

    if neighborInfo.appId == self.app.appId then
        local cell = self.byKey[neighborInfo.id]
        if not cell or cell.playerCount == 0 then return end
        local ghost = self:buildGhost(real, cell, real.x, real.y)
        ghost.realApp = self.app.appId
        cell:addEntity(ghost)
        real:addGhost({ key = key, app = self.app.appId, cellKey = neighborInfo.id, sameApp = true })
        return
    end

    local snapshot = real:ghostSnapshot()
    local ok = self.app:call(neighborInfo.appId, "ghost_create", self.spaceId, neighborInfo.id, {
        realId = real.id, kind = real.kind, x = real.x, y = real.y,
        snapshot = snapshot, fromApp = self.app.appId,
        ownerCellKey = real.cell.info.id, promote = false,
    })
    if ok then
        real:addGhost({ key = key, app = neighborInfo.appId, cellKey = neighborInfo.id })
    end
end

function LocalSpace:buildGhost(real, cell, x, y)
    local def = defs.get(real.kind) or real.def
    local ghost = entities.GhostEntity.new(def, self.app:nextId(), real.kind, self, cell, real.id, x, y)
    if real.props then
        for name, value in pairs(real.props:dump()) do ghost:stageProp(name, value) end
    end
    return ghost
end

-- 远端请求创建 ghost(可能用于迁移 promote)
function LocalSpace:onGhostCreate(cellKey, req)
    local cell = self.byKey[cellKey]
    if not cell then return false end

    local ghost = self:findGhost(req.realId, cellKey)
    if ghost then return true end

    local def = defs.get(req.kind)
    if not def then return false end

    ghost = entities.GhostEntity.new(def, self.app:nextId(), req.kind, self, cell, req.realId, req.x, req.y)
    if req.snapshot then
        ghost.props:load(req.snapshot.props or {})
    end
    ghost.realApp = req.fromApp
    ghost.realCellKey = req.ownerCellKey
    ghost.promote = req.promote

    cell:addEntity(ghost)
    return true
end

function LocalSpace:findGhost(realId, cellKey)
    local cell = self.byKey[cellKey]
    if not cell then return nil end
    for _, entity in pairs(cell.entities) do
        if entity.isGhost and entity.realId == realId then return entity end
    end
end

-- ghost 提升为 real(跨 app 迁移终点)
function LocalSpace:onGhostPromote(cellKey, realId, req)
    local ghost = self:findGhost(realId, cellKey)
    if not ghost then return false end

    local cell = self.byKey[cellKey]
    local def = ghost.def
    local real = entities.RealEntity.new(def, realId, ghost.kind, self, cell, ghost.x, ghost.y)
    real.props:load(ghost.props:dump())

    -- 继承 ghost 对端信息
    real.ghosts = {}
    for _, peer in ipairs(req.peers or {}) do
        if peer.sameApp then
            real:addGhost({ app = peer.app, cellKey = peer.cellKey, sameApp = true })
        else
            real:addGhost({ app = peer.app, cellKey = peer.cellKey })
        end
    end
    if req.witnessCellKey then
        real:addGhost({ app = req.fromApp, cellKey = req.witnessCellKey, witness = true })
    end

    cell:removeEntity(ghost)
    cell:addEntity(real)
    self.app:notifyEntityMoved(real)
    return true
end

-- 远端发来的属性同步
function LocalSpace:onGhostSync(cellKey, realId, props)
    local ghost = self:findGhost(realId, cellKey)
    if not ghost then return end
    for name, value in pairs(props or {}) do
        ghost:stageProp(name, value)
    end
end

-- 远端发来的 ghost 销毁
function LocalSpace:onGhostDestroy(cellKey, realId)
    local cell = self.byKey[cellKey]
    local ghost = self:findGhost(realId, cellKey)
    if ghost and cell then
        cell:removeEntity(ghost)
    end
end

-- real 属性变更后广播给所有 ghost
function LocalSpace:broadcastGhost(real, props)
    for _, info in pairs(real.ghosts) do
        if info.sameApp then
            local ghost = self:findGhost(real.id, info.cellKey)
            if ghost then
                for name, value in pairs(props) do ghost:stageProp(name, value) end
            end
        else
            self.app:send(info.app, "ghost_sync", self.spaceId, info.cellKey, real.id, props)
        end
    end
end

M.LocalSpace = LocalSpace
return M
