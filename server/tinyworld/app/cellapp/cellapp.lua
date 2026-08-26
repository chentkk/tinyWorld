-- tinyworld/app/cellapp.lua
-- cellapp 服务: 一个 skynet 服务相当于 bigworld 的一个 cellapp。
-- 内部通过局部 space(localspace) 管理运行在本 app 上的 cell, 主循环用
-- skynet.fork 运行, 以 cell:tick(dt) 为主体更新。

local skynet = require "skynet"
local service = require "tinyworld.core.service"
local log = require "tinyworld.core.log"
local proto = require "tinyworld.core.proto"
local util = require "tinyworld.core.util"
local localSpaceMod = require "tinyworld.app.cellapp.local_space"
local defs = require "tinyworld.entity.defs"
local entities = require "tinyworld.app.cellapp.entities"

local cmd = {}
local selfApp = setmetatable({}, { __index = cmd })
selfApp.appId = nil
selfApp.world = nil
selfApp.space = nil
selfApp.localSpace = nil
selfApp.reals = {}
selfApp.addrs = {} -- appId -> addr

function selfApp:now()
    return skynet.time()
end

function selfApp:nextId()
    return util.makeEntityId(selfApp.appId)
end

function selfApp:call(appId, command, ...)
    local addr = selfApp.addrs[appId]
    if not addr then
        addr = skynet.call(selfApp.world, "lua", "cellapp_addr", appId)
        selfApp.addrs[appId] = addr
    end
    if not addr then return nil end
    return skynet.call(addr, "lua", command, ...)
end

function selfApp:send(appId, command, ...)
    local addr = selfApp.addrs[appId]
    if not addr then
        addr = skynet.call(selfApp.world, "lua", "cellapp_addr", appId)
        selfApp.addrs[appId] = addr
    end
    if addr then
        skynet.send(addr, "lua", command, ...)
    end
end

function selfApp:sendToClient(player, msg)
    if player.baseApp then
        msg.playerId = player.playerId or player.clientId
        log.debug("cellapp sendToClient entity=%s playerId=%s t=%s",
            tostring(player.clientId), tostring(msg.playerId), tostring(msg.t))
        skynet.send(player.baseApp, "lua", "client_send", msg)
    else
        log.warn("cellapp sendToClient no baseApp entity=%s", tostring(player.clientId))
    end
end

function selfApp:notifyEntityMoved(real)
    -- 跨 cellapp 迁移完成后回调
    log.info("entity %s promoted on app %d", real.clientId, selfApp.appId)
end

-- 注册一个真身实体(供业务查找)
function selfApp:indexReal(real)
    selfApp.reals[real.id .. "@" .. real.cell.info.id] = real
end

function cmd.init(spaceId, worldAddr)
    selfApp.appId = skynet.self()
    selfApp.world = worldAddr

    local gameInit = require "game.init"
    gameInit.registerCellDefs()

    local ret = skynet.call(worldAddr, "lua", "cellapp_register", spaceId, skynet.self())
    if not ret then
        log.fatal("register cellapp fail")
        skynet.exit()
        return
    end

    selfApp.appId = ret.appId
    selfApp.space = ret.space
    selfApp.addrs = {}
    for appId, addr in pairs(ret.allAddrs or {}) do
        selfApp.addrs[appId] = addr
    end
    selfApp.addrs[ret.appId] = skynet.self()

    local spaceModule = require(skynet.getenv("space_config") or "game.config.spaces")
    local rawConf
    for _, s in ipairs(spaceModule.spaces) do
        if s.id == spaceId then rawConf = s end
    end
    rawConf = rawConf or { id = spaceId }

    local spaceLib = require "tinyworld.space.space"
    selfApp.spaceConfig = spaceLib.SpaceConfig.compile(rawConf, spaceModule.defaultCellApps)

    local localSpace = localSpaceMod.LocalSpace.new(selfApp)
    for _, cellInfo in ipairs(ret.cells) do
        localSpace:addLocalCell({
            cx = cellInfo.cx, cy = cellInfo.cy,
            x = cellInfo.x, y = cellInfo.y,
            w = cellInfo.w, h = cellInfo.h,
            appId = cellInfo.appId,
            id = cellInfo.id,
        })
    end
    selfApp.localSpace = localSpace

    skynet.fork(function()
        local frameTime = 0.1
        local frame = 0
        while true do
            local t1 = skynet.time()
            local dt = skynet.time() - (selfApp.lastTickTime or skynet.time())
            selfApp.lastTickTime = skynet.time()
            localSpace:tick(dt > frameTime * 2 and frameTime or dt)
            if gameInit and gameInit.onCellAppTick then
                gameInit.onCellAppTick(dt > frameTime * 2 and frameTime or dt)
            end

            -- 定期上报负载: real 数量 + 每帧 cpu(平滑)
            frame = frame + 1
            if frame % 10 == 0 then
                local realCount = 0
                for _, cell in ipairs(localSpace.cells) do
                    for _, e in pairs(cell.entities) do
                        if e.isReal then realCount = realCount + 1 end
                    end
                end
                local cpu = 0
                local used = skynet.time() - t1
                if frameTime > 0 then cpu = used / frameTime end
                skynet.send(worldAddr, "lua", "cellapp_report", ret.appId, spaceId, realCount, cpu)
            end
            skynet.sleep(10) -- 0.1s = 10 * 0.01s
        end
    end)

    log.info("cellapp %d ready, cells=%d", ret.appId, #localSpace.cells)
    return { appId = ret.appId }
end

-- 业务层真正创建真身实体
function cmd.spawn_entity(spaceId, cellKey, kind, data, baseApp)
    local cell = selfApp.localSpace and selfApp.localSpace:getCell(cellKey)
    if not cell then return nil, "cell not local" end

    local def = defs.get(kind)
    if not def then return nil, "unknown kind " .. tostring(kind) end

    local entityId = selfApp:nextId()
    local real = entities.RealEntity.new(def, entityId, kind, selfApp.localSpace, cell)
    real.playerId = data and data.playerId
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
    require("game.init").setupCellEntity(real, data or {})

    cell:addEntity(real)
    selfApp:indexReal(real)

    local props = entities.clientProps(real)
    return { entityId = entityId, cellKey = cellKey, kind = kind, props = props }
end

function cmd.call_cell_rpc(spaceId, entityId, cellKey, name, data)
    local cell = selfApp.localSpace:getCell(cellKey)
    if not cell then return nil, "cell not local" end

    local real = cell:get(entityId)
    if not real or not real.isReal then return nil, "entity not found" end

    return real:dispatchClientRpc(name, data)
end

-- 供 baseapp 存盘前取 cell 侧最新属性(坐标等)
function cmd.get_entity(spaceId, entityId)
    for _, cell in ipairs(selfApp.localSpace.cells) do
        local e = cell:get(entityId)
        if e then
            return { cellKey = cell.info.id,
                     props = { x = e.x, y = e.y } }
        end
    end
end

function cmd.find_entity(spaceId, entityId)
    for _, cell in ipairs(selfApp.localSpace.cells) do
        local e = cell:get(entityId)
        if e then return cell.info.id end
    end
end

-- 内部: ghost 流程
function cmd.ghost_create(spaceId, cellKey, req)
    return selfApp.localSpace:onGhostCreate(cellKey, req)
end

function cmd.ghost_promote(spaceId, cellKey, realId, req)
    return selfApp.localSpace:onGhostPromote(cellKey, realId, req)
end

function cmd.ghost_sync(spaceId, cellKey, realId, props)
    selfApp.localSpace:onGhostSync(cellKey, realId, props)
end

function cmd.ghost_destroy(spaceId, cellKey, realId)
    selfApp.localSpace:onGhostDestroy(cellKey, realId)
end

function cmd.ghost_rpc(spaceId, cellKey, realId, name, data)
    local ghost = selfApp.localSpace:findGhost(realId, cellKey)
    if ghost then
        return ghost:dispatchGhostRpc(name, data)
    end
end

function cmd.real_rpc(spaceId, cellKey, realId, name, data)
    local cell = selfApp.localSpace:getCell(cellKey)
    local real = cell and cell:get(realId)
    if real and real.isReal then
        return real:dispatchRealRpc(name, data)
    end
end

function cmd.get_cell(spaceId, cellKey)
    local cell = selfApp.localSpace:getCell(cellKey)
    if not cell then return nil end
    return { entities = util.count(cell.entities) }
end

service.startService("cellapp", nil, cmd)
return cmd
