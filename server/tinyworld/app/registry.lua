-- tinyworld/app/registry.lua
-- 服务地址注册表。框架底层服务启动时前往注册自己的地址,
-- 后续启动的服务启动时查询依赖地址并缓存在自身。
-- 底层服务地址固定, 因此调用方一次查询、长期使用。

local skynet = require "skynet"
local service = require "tinyworld.core.service"
local log = require "tinyworld.core.log"

local cmd = {}
local services = {} -- name -> addr

function cmd.ping()
    return true
end

function cmd.register(name, addr)
    assert(type(name) == "string" and name ~= "", "registry: empty service name")
    assert(type(addr) == "number", "registry: bad address")

    if services[name] then
        log.warn("registry: overwrite address for %s", name)
    end
    services[name] = addr
    log.info("registry: register %s addr=%s", name, skynet.address(addr))
    return true
end

function cmd.query(name)
    return services[name]
end

function cmd.list()
    local out = {}
    for name, addr in pairs(services) do
        out[name] = skynet.address(addr)
    end
    return out
end

service.startService("registry", nil, cmd)
return cmd
