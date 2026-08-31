-- tinyworld/app/logservice.lua
-- 协议日志服务: gate 收发消息后调用本服务记录到 message.log。
-- 保证出现在文件中的消息都是已实际收发的内容, 便于调试。

local skynet = require "skynet"
local service = require "tinyworld.core.service"
local log = require "tinyworld.core.log"

local file
local path
local registry

local function openFile()
    path = skynet.getenv("log_dir") or "./"
    local f = io.open(path .. "/message.log", "a")
    if not f then error("open message.log fail: " .. path) end
    return f
end

local cmd = {}

function cmd.write(connId, kind, msgType, name, data)
    if not file then file = openFile() end

    local sec = math.floor(skynet.time())
    local stamp = os.date("%Y-%m-%d %H:%M:%S", sec) ..
        string.format(".%03d", math.floor((skynet.time() - sec) * 1000))
    local line
    if kind == "" then
        -- connect / disconnect 等无协议类型的事件, 不带大括号
        line = string.format("[%s][%s] %s\n", stamp, connId, data or "")
    else
        line = string.format("[%s][%s] %s %s %s %s\n",
            stamp, connId, kind, msgType, name or "", data or "")
    end
    file:write(line)
    file:flush()
end

function cmd.init(registryAddr)
    registry = registryAddr
    file = openFile()

    local addr = skynet.self()
    skynet.call(registry, "lua", "register", "log", addr)
    log.info("logservice ready, path=%s", path)
end

service.startService("logservice", nil, cmd)
