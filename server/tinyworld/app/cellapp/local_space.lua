-- tinyworld/app/cellapp/local_space.lua
-- 局部的 space: 仅作为数据边界。
-- 提供:
--   - 本 cellapp 上运行的 cell 集合
--   - space 公共数据(网格 / cell 划分 / aoi 等)
--   - 远端 cellapp 发来的 ghost 协议入口
-- 迁移策略 / ghost 维护 / 属性广播等行为都归属 Cell。

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

-- 远端迁移结束: ghost 在本 cell 提升为 real
function LocalSpace:onGhostPromote(cellKey, realId, req)
    local cell = self.byKey[cellKey]
    if not cell then return false end

    local ghost = cell:findGhost(realId)
    if not ghost then return false end

    local real = entities.RealEntity.new(ghost.def, realId, ghost.kind, self, cell, ghost.x, ghost.y)
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

-- 边界出口: real 的 dirty 属性同步给所有 ghost
-- 本地 ghost 直接 stage, 远端 ghost 通过 cellapp 消息 stage
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
