-- tinyworld/app/cellapp/cellapp.lua
-- cellapp 服务: 一个 skynet 服务相当于 bigworld 的一个 cellapp。
-- 内部通过局部 space(localspace) 管理运行在本 app 上的 cell, 主循环用
-- skynet.fork 运行, 以 cell:tick(dt) 为主体更新。

local skynet = require "skynet"
local service = require "tinyworld.core.service"
local log = require "tinyworld.core.log"
local proto = require "tinyworld.core.proto"
local util = require "tinyworld.core.util"
local LocalSpace = require "tinyworld.app.cellapp.local_space"
local defs = require "tinyworld.entity.defs"
local entityMsg = require "tinyworld.app.cellapp.entity_msg"
local RealEntity = require "tinyworld.app.cellapp.real_entity"

local cmd = {}
local cellapp = setmetatable({}, { __index = cmd })
cellapp.appId = nil
cellapp.world = nil
cellapp.spaces = {}  -- spaceId -> LocalSpace; 一个 cellapp 可运行多个 space
cellapp.reals = {}
cellapp.addrs = {} -- appId -> addr

-- 取本 app 某空间里的本地 cell(多数命令按 spaceId 定位)
local function getLocalCell(spaceId, cellKey)
    local space = cellapp.spaces[spaceId]
    return space and space:getCell(cellKey)
end

function cellapp:now()
    return skynet.time()
end

function cellapp:nextId()
    return util.makeEntityId(cellapp.appId)
end

function cellapp:call(appId, command, ...)
    local addr = cellapp.addrs[appId]
    if not addr then
        addr = skynet.call(cellapp.world, "lua", "cellapp_addr", appId)
        cellapp.addrs[appId] = addr
    end
    if not addr then return nil end
    return skynet.call(addr, "lua", command, ...)
end

function cellapp:send(appId, command, ...)
    local addr = cellapp.addrs[appId]
    if not addr then
        addr = skynet.call(cellapp.world, "lua", "cellapp_addr", appId)
        cellapp.addrs[appId] = addr
    end
    if addr then
        skynet.send(addr, "lua", command, ...)
    end
end

function cellapp:sendToClient(player, msg)
    if player.baseApp then
        msg.playerId = player.playerId or player.clientId
        log.debug("cellapp sendToClient entity=%s playerId=%s t=%s",
            tostring(player.clientId), tostring(msg.playerId), tostring(msg.t))
        skynet.send(player.baseApp, "lua", "client_send", msg)
    else
        log.warn("cellapp sendToClient no baseApp entity=%s", tostring(player.clientId))
    end
end

function cellapp:notifyEntityMoved(real)
    -- 跨 cellapp 迁移完成后回调
    log.info("entity %s promoted on app %d", real.clientId, cellapp.appId)
end

-- 注册一个真身实体(供业务查找)
function cellapp:indexReal(real)
    cellapp.reals[real.id .. "@" .. real.cell.info.id] = real
end

function cmd.init(registryAddr, index, gameConfig)
    index = index or 1
    cellapp.world = skynet.call(registryAddr, "lua", "query", "world")
    assert(cellapp.world, "world not registered")

    skynet.call(registryAddr, "lua", "register", "cellapp." .. index, skynet.self())

    require("tinyworld.combat.env").setIsServer(true)

    local entityDefs = gameConfig and gameConfig.entityDefs or {}
    for _, bootModule in ipairs(entityDefs.cell and entityDefs.cell.boot or {}) do
        require(bootModule)
    end
    defs.registerList(entityDefs.cell and entityDefs.cell.defs)

    local ret = skynet.call(cellapp.world, "lua", "cellapp_register", skynet.self())
    if not ret then
        log.fatal("register cellapp fail")
        skynet.exit()
        return
    end

    cellapp.appId = ret.appId
    cellapp.addrs = {}
    for appId, addr in pairs(ret.allAddrs or {}) do
        cellapp.addrs[appId] = addr
    end
    cellapp.addrs[ret.appId] = skynet.self()

    skynet.fork(function()
        local frameTime = 0.1
        local frame = 0
        while true do
            local t1 = skynet.time()
            local dt = skynet.time() - (cellapp.lastTickTime or skynet.time())
            cellapp.lastTickTime = skynet.time()
            local step = dt > frameTime * 2 and frameTime or dt

            -- 本 cellapp 上运行的每个 space 独立 tick
            local realBySpace = {}
            for spaceId, space in pairs(cellapp.spaces) do
                space:tick(step)
                local realCount = 0
                for _, cell in ipairs(space.cells) do
                    for _, e in pairs(cell.entities) do
                        if e.isReal then realCount = realCount + 1 end
                    end
                end
                realBySpace[spaceId] = realCount
            end

            frame = frame + 1
            if frame % 10 == 0 then
                for spaceId, realCount in pairs(realBySpace) do
                    local cpu = 0
                    local used = skynet.time() - t1
                    if frameTime > 0 then cpu = used / frameTime end
                    skynet.send(cellapp.world, "lua", "cellapp_report",
                        cellapp.appId, spaceId, realCount, cpu)
                end
            end
            skynet.sleep(10) -- 0.1s = 10 * 0.01s
        end
    end)

    log.info("cellapp %d ready (waiting for space binding)", ret.appId)
    return { appId = ret.appId }
end

-- world 创建 space 后下发本 app 负责的 cells。
-- 空间切分由 world 根据 spaceDef 完成, 本服务只重建一个几何一致的本地视图,
-- 并把 world 分配的 appId 回填到 cell 上。
function cmd.bind_cells(spaceId, spaceDef, cellAssignments, cells)
    local SpaceConfig = require "tinyworld.space.space"
    local config = SpaceConfig.compile(spaceDef)
    for cellId, appId in pairs(cellAssignments or {}) do
        local info = config.byCellId[cellId]
        if info then info.appId = appId end
    end

    local space = LocalSpace.new(cellapp, config, cells)
    cellapp.spaces[spaceId] = space
    log.info("cellapp %d bound space %s cells=%d", cellapp.appId, spaceId, #cells)
    return true
end

-- 业务层真正创建真身实体
function cmd.spawn_entity(spaceId, cellKey, kind, data, baseApp)
    local cell = getLocalCell(spaceId, cellKey)
    if not cell then return nil, "cell not local" end

    local def = defs.get(kind)
    if not def then return nil, "unknown kind " .. tostring(kind) end

    -- 玩家 cell entity 使用 playerId(全服唯一), 其他对象(怪物/projectile)使用 app 分配 id
    local playerId = data and data.playerId
    local entityId = playerId or cellapp:nextId()
    local space = cellapp.spaces[spaceId]
    local real = RealEntity.new(def, entityId, kind, space, cell)
    real.playerId = playerId
    real.cellInitData = data and data.initData
    local x = data and data.x or cell.info.x + cell.info.w / 2
    local y = data and data.y or cell.info.y + cell.info.h / 2
    real.x = x
    real.y = y
    real.baseApp = baseApp

    local spawnProps = { x = x, y = y }
    if data.props then
        for k, v in pairs(data.props) do spawnProps[k] = v end
    end
    real.props:load(spawnProps)
    real:onCreate()
    real:setupComponents(def.cellComponents)
    real:openViews(def.cellOpenViews)

    cell:addEntity(real)
    cellapp:indexReal(real)
    real.readyForSync = true

    local info = entityMsg.entitySpawnInfo(real)
    info.cellKey = cellKey
    return info
end

function cmd.call_cell_rpc(spaceId, entityId, cellKey, name, data)
    local cell = getLocalCell(spaceId, cellKey)
    if not cell then return nil, "cell not local" end

    local real = cell:get(entityId)
    if not real or not real.isReal then return nil, "entity not found" end

    return real:dispatchClientRpc(name, data)
end

-- 供 baseapp 存盘前取 cell 侧最新属性(坐标等)
function cmd.get_entity(spaceId, entityId)
    local space = cellapp.spaces[spaceId]
    for _, cell in ipairs(space and space.cells or {}) do
        local e = cell:get(entityId)
        if e then
            return { cellKey = cell.info.id,
                     props = { x = e.x, y = e.y } }
        end
    end
end

function cmd.find_entity(spaceId, entityId)
    local space = cellapp.spaces[spaceId]
    for _, cell in ipairs(space and space.cells or {}) do
        local e = cell:get(entityId)
        if e then return cell.info.id end
    end
end

-- 内部: ghost 流程
function cmd.ghost_create(spaceId, cellKey, req)
    local cell = getLocalCell(spaceId, cellKey)
    if not cell then return false end
    return cell:upsertRemoteGhost(req)
end

function cmd.ghost_promote(spaceId, cellKey, realId, req)
    local cell = getLocalCell(spaceId, cellKey)
    if not cell then return false end

    local real = cell:promoteGhost(realId, req)
    if not real then return false end

    -- 迁移后重新装配 cell 侧组件(移动 / 战斗同步等)
    real:setupComponents(real.def.cellComponents)
    real:openViews(real.def.cellOpenViews)
    real.readyForSync = true

    if real.baseApp then
        skynet.send(real.baseApp, "lua", "rebind_cell",
            real.playerId, spaceId, cellKey, skynet.self())
    end
    return true
end

function cmd.ghost_reparent(spaceId, cellKey, realId, realApp, realCellKey)
    local cell = getLocalCell(spaceId, cellKey)
    local ghost = cell and cell:findGhost(realId)
    if ghost then ghost:reparent(realApp, realCellKey) end
end

function cmd.ghost_sync(spaceId, cellKey, realId, props)
    local cell = getLocalCell(spaceId, cellKey)
    if cell then cell:applyRemoteGhostSync(realId, props) end
end

function cmd.ghost_destroy(spaceId, cellKey, realId)
    local cell = getLocalCell(spaceId, cellKey)
    if cell then cell:destroyRemoteGhost(realId) end
end

function cmd.ghost_rpc(spaceId, cellKey, realId, name, data)
    local cell = getLocalCell(spaceId, cellKey)
    local ghost = cell and cell:findGhost(realId)
    if ghost then
        return ghost:dispatchGhostRpc(name, data)
    end
end

function cmd.real_rpc(spaceId, cellKey, realId, name, data)
    local cell = getLocalCell(spaceId, cellKey)
    local real = cell and cell:get(realId)
    if real and real.isReal then
        return real:dispatchRealRpc(name, data)
    end
end

function cmd.get_cell(spaceId, cellKey)
    local cell = getLocalCell(spaceId, cellKey)
    if not cell then return nil end
    return { entities = util.count(cell.entities) }
end

service.startService("cellapp", nil, cmd)
return cmd
