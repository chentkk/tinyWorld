-- tinyworld/app/world.lua
-- world 服务: 分布式场景管理中心。
-- 保存完整 space 信息, 由 world 读取 space 配置并完成:
--   cell 切分(自动/手动) -> 运行时从已注册 cellapp 池分配 app -> 下发给 cellapp。
-- 之后由 world 维护 cellapp 地址与负载, 供 spawn / 迁移使用。

local skynet = require "skynet"
local service = require "tinyworld.core.service"
local log = require "tinyworld.core.log"
local ServerSpace = require "tinyworld.app.world.server_space"
local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LoadBalancer = require "tinyworld.app.world.load_balancer"

local cmd = {}
local spaces = {}
local spaceDefs = {}          -- spaceId -> 原始 space 配置(仅几何, 不含 cellapp)
local cellapps = {}           -- appId -> { addr, realCount, cpu }
local nextAppId = 0
local registry

local function orderedAppIds()
    local ids = {}
    for appId in pairs(cellapps) do
        ids[#ids + 1] = appId
    end
    table.sort(ids)
    return ids
end

-- cellapp 池为配置中的某个 space 做运行时分配(当前: 顺序轮询)
local function pickAppsForSpace()
    return orderedAppIds()
end

-- space 配置完整性与感知范围校验
local function validateSpaceDef(def)
    assert(def.id, "space def missing id")
    assert(tonumber(def.width) and tonumber(def.width) > 0, "space " .. tostring(def.id) .. ": bad width")
    assert(tonumber(def.height) and tonumber(def.height) > 0, "space " .. tostring(def.id) .. ": bad height")
    assert(tonumber(def.aoiRange) and tonumber(def.aoiRange) > 0, "space " .. tostring(def.id) .. ": bad aoiRange")
    assert(tonumber(def.ghostRange), "space " .. tostring(def.id) .. ": missing ghostRange")
    assert(tonumber(def.ghostRange) > tonumber(def.aoiRange),
        "space " .. tostring(def.id) .. ": ghostRange must be greater than aoiRange")
    assert(def.cells or def.cellSize or def.cellCols or def.cellRows,
        "space " .. tostring(def.id) .. ": missing cell definition")
end

function cmd.init(registryAddr, gameConfig)
    registry = registryAddr

    local spacesConfig = gameConfig and gameConfig.spaces or {}
    for _, spaceDef in ipairs(spacesConfig.spaces or {}) do
        validateSpaceDef(spaceDef)
        spaceDefs[spaceDef.id] = spaceDef
        log.info("space def %s loaded", spaceDef.id)
    end

    skynet.call(registry, "lua", "register", "world", skynet.self())
    log.info("world ready")
end

-- 运行期创建 space。space 的几何/AOI 全部取自配置, 归属由 world 运行时分配。
function cmd.create_space(spaceId)
    if spaces[spaceId] then
        return spaces[spaceId]:dump()
    end

    local def = spaceDefs[spaceId]
    if not def then return nil, "space def not found: " .. tostring(spaceId) end

    local appIds = pickAppsForSpace()
    if #appIds == 0 then return nil, "no cellapp registered" end

    -- 1) SpaceConfig 只切分 cell, 2) world 侧运行时分配 cellapp
    local config = SpaceConfig.compile(def)
    local ok, byApp = CellAllocator.distribute(config, appIds)
    if not ok then return nil, byApp end

    -- 每个 cellapp 都需要完整的 cell -> appId 映射来重建本地空间视图
    local assignments = {}
    for _, info in ipairs(config.cells) do
        assignments[info.id] = info.appId
    end

    local space = ServerSpace.new(def, config)
    spaces[spaceId] = space

    for appId, cells in pairs(byApp) do
        local reg = cellapps[appId]
        if reg and reg.addr then
            skynet.call(reg.addr, "lua", "bind_cells", spaceId, def, assignments, cells)
            log.info("space %s assigned %d cells to cellapp %d", spaceId, #cells, appId)
        else
            log.warn("space %s: cellapp %d not registered", spaceId, appId)
        end
    end

    log.info("space %s created cells=%d apps=%d", spaceId, #config.cells, #appIds)
    return space:dump()
end

function cmd.query_space(spaceId)
    local space = spaces[spaceId]
    if not space then return nil end
    return space:dump()
end

-- cellapp 启动注册: world 记录运行时地址, 不依赖某个 space 已存在
function cmd.cellapp_register(addr)
    nextAppId = nextAppId + 1
    local appId = nextAppId
    cellapps[appId] = { addr = addr, realCount = 0, cpu = 0 }

    local allAddrs = {}
    for id, reg in pairs(cellapps) do
        allAddrs[id] = reg.addr
    end

    log.info("cellapp %d registered addr=%s", appId, skynet.address(addr))
    return { appId = appId, allAddrs = allAddrs }
end

function cmd.cellapp_addr(appId)
    local reg = cellapps[appId]
    return reg and reg.addr
end

function cmd.spawn_info(spaceId, x, y)
    local space = spaces[spaceId]
    if not space then return nil, "space not found" end

    local cell = space:chooseSpawnCell(x, y)
    local reg = cellapps[cell.appId]
    return { spaceId = spaceId, cell = cell:dump(), appId = cell.appId,
             appAddr = reg and reg.addr }
end

function cmd.cellapp_report(appId, spaceId, realCount, cpu)
    local reg = cellapps[appId]
    local space = spaces[spaceId]
    if not reg or not space then return nil end

    reg.realCount = realCount
    reg.cpu = cpu

    if not space.balancer then
        space.balancer = LoadBalancer.new(space.config)
    end

    local smooth = space.balancer:report(appId, realCount, cpu, nil)
    local advice = space.balancer:tick()
    if advice and advice ~= 0 then
        log.debug("space %s balance advice=%d (strategy 2)", spaceId, advice)
    end
    return smooth
end

function cmd.stats(spaceId)
    local space = spaces[spaceId]
    if not space or not space.balancer then return {} end
    local out = {}
    for appId, st in pairs(space.balancer.stats) do
        out[#out + 1] = { appId = appId, realCount = st.realCount,
                          rawCpu = st.rawCpu, smoothCpu = st.smoothCpu }
    end
    return out
end

service.startService("world", nil, cmd)
