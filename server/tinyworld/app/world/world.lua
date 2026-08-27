-- tinyworld/app/world.lua
-- world 服务: 代替 bigworld 的 cellmgr。保存完整 space 信息(serverspace),
-- 负责给 cellapp 分配 cell、注册 cellapp 地址、汇总负载上报。

local skynet = require "skynet"
local service = require "tinyworld.core.service"
local log = require "tinyworld.core.log"
local ServerSpace = require "tinyworld.app.world.server_space"
local LoadBalancer = require "tinyworld.app.world.load_balancer"

local cmd = {}
local spaces = {}
local appRegistry = {} -- appId -> { addr, realCount, cpu }
local nextAppId = 0

local function spaceConfigModule()
    return skynet.getenv("space_config") or "game.config.spaces"
end

local function init()
    local mod = require(spaceConfigModule())
    for _, spaceDef in ipairs(mod.spaces or {}) do
        local space = ServerSpace.new(spaceDef, mod.defaultCellApps)
        spaces[space.id] = space
        log.info("space %s loaded, cells=%d", space.id, #space.config.cells)
    end
end

-- 运行期创建 space(配置文件中 space 定义已加载则直接返回)
function cmd.create_space(spaceId)
    local space = spaces[spaceId]
    if space then return space:dump() end

    local mod = require(spaceConfigModule())
    for _, spaceDef in ipairs(mod.spaces or {}) do
        if spaceDef.id == spaceId then
            space = ServerSpace.new(spaceDef, mod.defaultCellApps)
            spaces[spaceId] = space
            return space:dump()
        end
    end
    return nil
end

function cmd.query_space(spaceId)
    local space = spaces[spaceId]
    if not space then return nil end
    return space:dump()
end

function cmd.cellapp_register(spaceId, addr)
    local space = spaces[spaceId]
    if not space then return nil end

    nextAppId = nextAppId + 1
    local appId = nextAppId
    appRegistry[appId] = { addr = addr, realCount = 0, cpu = 0 }

    local cells = {}
    for _, info in ipairs(space.config.cells) do
        if info.appId == appId then
            cells[#cells + 1] = info:dump()
        end
    end

    log.info("cellapp %d registered addr=%s cells=%d", appId, skynet.address(addr), #cells)

    -- 汇总当前已注册 cellapp 的地址映射, 便于 cellapp 间直接互调
    local allAddrs = {}
    for id, reg in pairs(appRegistry) do
        allAddrs[id] = reg.addr
    end

    return { appId = appId, space = space:dump(), cells = cells,
             allApps = space.config.appIds, allAddrs = allAddrs }
end

function cmd.cellapp_addr(appId)
    local reg = appRegistry[appId]
    return reg and reg.addr
end

function cmd.spawn_info(spaceId, x, y)
    local space = spaces[spaceId]
    if not space then return nil, "space not found" end

    local cell = space:chooseSpawnCell(x, y)
    local reg = appRegistry[cell.appId]
    return { spaceId = spaceId, cell = cell:dump(), appId = cell.appId,
             appAddr = reg and reg.addr }
end

function cmd.cellapp_report(appId, spaceId, realCount, cpu)
    local space = spaces[spaceId]
    if not space or not appRegistry[appId] then return nil end

    appRegistry[appId].realCount = realCount
    appRegistry[appId].cpu = cpu

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

service.startService("world", init, cmd)
