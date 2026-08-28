-- tinyworld/app/boot.lua
-- 框架启动入口。负责按依赖顺序创建并初始化框架底层服务:
-- registry -> logservice -> dbmgr -> world -> login -> baseapp(s) -> gate(s) -> cellapp(s)
-- 框架服务地址统一注册进 registry, 各服务启动时查询依赖地址并缓存。
-- 框架启动完成后, 再调用 game.main 启动游戏业务服务。

local skynet = require "skynet"
require "skynet.manager"

local function staticInt(name, default)
    return tonumber(skynet.getenv(name)) or default
end

local function staticStr(name, default)
    return skynet.getenv(name) or default
end

-- 创建服务并等待其 init 完成(init 返回说明服务 ready)
local function startService(name, initName, ...)
    local addr = skynet.newservice(name)
    skynet.call(addr, "lua", initName or "init", ...)
    return addr
end

skynet.start(function()
    local gameConfig = require(staticStr("game_config", "game.config"))

    local registry = skynet.newservice("registry")
    skynet.call(registry, "lua", "ping")

    -- 无依赖: logservice 只注册自己
    startService("logservice", "init", registry)

    -- dbmgr 只依赖 registry, 内部创建并持有 db 服务
    startService("dbmgr", "init", registry, gameConfig)

    -- world / login: 先注册, 后续服务可查询
    local world = startService("world", "init", registry, gameConfig)
    startService("login", "init", registry)

    -- baseapp(s)
    local baseappCount = staticInt("baseapp_count", 1)
    for i = 1, baseappCount do
        startService("baseapp", "init", registry, i, gameConfig)
    end

    -- gate(s)
    local gateCount = staticInt("gate_count", 1)
    local ports = {}
    for port in (staticStr("gate_ports", "8000")):gmatch("%d+") do
        ports[#ports + 1] = tonumber(port)
    end
    for i = 1, gateCount do
        startService("gate", "init", registry, ports[i] or (8000 + i - 1), i)
    end

    -- cellapp(s): 先注册到 world 的 cellapp 池, 尚不绑定任何 space
    local cellappCount = staticInt("cellapp_count", 2)
    for i = 1, cellappCount do
        startService("cellapp", "init", registry, i, gameConfig)
    end

    -- world 创建默认地图: 切分 cell 并由 world 运行时为 cellapp 分配
    skynet.call(world, "lua", "create_space", staticStr("default_space", "main"))

    -- 框架就绪, 启动游戏业务服务
    local gameMain = require "game.main"
    if gameMain and gameMain.start then
        gameMain.start(registry)
    end

    skynet.error("tinyworld bootstrap done")
    skynet.exit()
end)
