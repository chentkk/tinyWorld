-- game/bootstrap.lua
-- 服务启动编排: 按依赖顺序创建服务并调用其 init 方法。
-- 顺序: logservice -> dbmgr -> world -> login -> baseapp(s) -> gate(s) -> cellapp(s)

local skynet = require "skynet"

skynet.start(function()
    local mgr = require "skynet.manager"

    local logAddr = skynet.newservice("logservice")
    skynet.setenv("addr_log", skynet.address(logAddr))

    local dbmgr = skynet.newservice("dbmgr")
    skynet.setenv("addr_dbmgr", skynet.address(dbmgr))

    local world = skynet.newservice("world")
    skynet.setenv("addr_world", skynet.address(world))

    local login = skynet.newservice("login")
    skynet.setenv("addr_login", skynet.address(login))

    local baseappCount = tonumber(skynet.getenv("baseapp_count")) or 1
    for i = 1, baseappCount do
        local addr = skynet.newservice("baseapp")
        skynet.setenv("baseapp_" .. i, skynet.address(addr))
    end

    local gateCount = tonumber(skynet.getenv("gate_count")) or 1
    local portsStr = skynet.getenv("gate_ports") or "8000"
    local ports = {}
    for port in portsStr:gmatch("%d+") do ports[#ports + 1] = tonumber(port) end
    for i = 1, gateCount do
        skynet.error("main: gate ", i)
        local addr = skynet.newservice("gate")
        skynet.setenv("gate_" .. i, skynet.address(addr))
        skynet.call(addr, "lua", "init", ports[i] or (8000 + i - 1), i)
        skynet.error("main: gate init ok ", i)
    end

    skynet.error("main: creating cellapps")
    local spaceConfig = require("game.config.spaces")
    local spaceId = spaceConfig.spaces[1].id
    local cellappCount = tonumber(skynet.getenv("cellapp_count")) or 2
    for i = 1, cellappCount do
        skynet.error("main: cellapp ", i)
        local addr = skynet.newservice("cellapp")
        skynet.error("main: call init ", skynet.address(addr))
        skynet.call(addr, "lua", "init", spaceId, world)
    end

    skynet.error("main done")
    skynet.exit()
end)
