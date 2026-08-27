-- tinyworld/app/cellapp/local_space.lua
-- 局部的 space: 管理本 cellapp 运行的 cell 集合。
-- 职责边界:
--   - 集合容器与 tick 驱动
--   - cellapp 之间的 ghost / 迁移协议协调
--   - 单一 cell 内部逻辑(迁移检查、ghost 维护、打包)归属 Cell

local class = require "tinyworld.core.class"
local cellMod = require "tinyworld.app.cellapp.cell"
local entities = require "tinyworld.app.cellapp.entities"
local defs = require "tinyworld.entity.defs"
local M = {}

local LocalSpace = class.makeClass("LocalSpace")

function LocalSpace:ctor(app)
    self.app = app
    self.config = app.spaceConfig
    self.cells = {}
    self.byKey = {}
    self.spaceId = app.spaceConfig.id
end

function LocalSpace:addLocalCell(cellInfo)
    local cell = cellMod.Cell.new(cellInfo, self.app, self)
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
end

-- 抗抖动策略: 是否允许 real 从当前 cell 迁入 ideal
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

    local sourceCell = real.cell
    local targetCell = self.byKey[ideal.id]
    if sourceCell and targetCell then
        -- 同 cellapp 迁移: 旧 cell 留下 witness ghost
        sourceCell:leaveWitness(real)
        sourceCell:removeEntity(real)
        real.cell = targetCell
        targetCell:addEntity(real)
        return true
    end

    return self:startRemoteMigration(real, ideal)
end

-- 跨 cellapp 迁移: 先在目标 app 建 ghost, 再降级为 witness, 最后提升
function LocalSpace:startRemoteMigration(real, ideal)
    real.migrating = true
    local snapshot = real:ghostSnapshot()

    local ok = self.app:call(ideal.appId, "ghost_create", self.spaceId, ideal.id, {
        realId = real.id, kind = real.kind, x = real.x, y = real.y,
        snapshot = snapshot, fromApp = self.app.appId,
        ownerCellKey = real.cell.info.id, promote = true,
    })

    if not ok then
        real.migrating = false
        return false
    end

    real.cell:leaveWitness(real)
    real.cell:removeEntity(real)

    local peers = self:collectGhostPeers(real)
    self.app:send(ideal.appId, "ghost_promote", self.spaceId, ideal.id, real.id, {
        fromApp = self.app.appId,
        witnessCellKey = real.cell.info.id,
        peers = peers,
    })
    real.migrating = nil
    return true
end

function LocalSpace:collectGhostPeers(real)
    local peers = {}
    for _, info in pairs(real.ghosts) do
        peers[#peers + 1] = { app = info.app, cellKey = info.cellKey, sameApp = info.sameApp }
    end
    return peers
end

-- 远端 cellapp 请求在本 cell 创建一个 ghost
function LocalSpace:onGhostCreate(cellKey, req)
    local cell = self.byKey[cellKey]
    if not cell then return false end
    if cell.playerCount == 0 then return false end

    local ghost = cell:findGhost(req.realId)
    if ghost then return true end

    local def = defs.get(req.kind)
    if not def then return false end

    ghost = entities.GhostEntity.new(def, self.app:nextId(), req.kind, self, cell, req.realId, req.x, req.y)
    if req.snapshot and req.snapshot.props then
        ghost.props:load(req.snapshot.props)
    end
    ghost.realApp = req.fromApp
    ghost.realCellKey = req.ownerCellKey
    ghost.promote = req.promote

    cell:addEntity(ghost)
    return true
end

-- ghost 提升为 real(跨 cellapp 迁移终点)
function LocalSpace:onGhostPromote(cellKey, realId, req)
    local cell = self.byKey[cellKey]
    if not cell then return false end

    local ghost = cell:findGhost(realId)
    if not ghost then return false end

    local def = ghost.def
    local real = entities.RealEntity.new(def, realId, ghost.kind, self, cell, ghost.x, ghost.y)
    real.props:load(ghost.props:dump())

    real.ghosts = {}
    for _, peer in ipairs(req.peers or {}) do
        real:addGhost({ app = peer.app, cellKey = peer.cellKey, sameApp = peer.sameApp })
    end
    if req.witnessCellKey then
        real:addGhost({ app = req.fromApp, cellKey = req.witnessCellKey, witness = true })
    end

    cell:removeEntity(ghost)
    cell:addEntity(real)
    self.app:notifyEntityMoved(real)
    return true
end

function LocalSpace:onGhostSync(cellKey, realId, props)
    local cell = self.byKey[cellKey]
    if not cell then return end

    local ghost = cell:findGhost(realId)
    if not ghost then return end
    for name, value in pairs(props or {}) do
        ghost:stageProp(name, value)
    end
end

function LocalSpace:onGhostDestroy(cellKey, realId)
    local cell = self.byKey[cellKey]
    if not cell then return end

    local ghost = cell:findGhost(realId)
    if ghost then cell:removeEntity(ghost) end
end

-- real 属性变更后广播给所有 ghost。
-- 本地 ghost 立即 stage, 远端 ghost 通过 cellapp 服务消息 stage。
function LocalSpace:broadcastGhost(real, props)
    for _, info in pairs(real.ghosts) do
        if info.sameApp then
            local cell = self.byKey[info.cellKey]
            local ghost = cell and cell:findGhost(real.id)
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
