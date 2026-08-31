-- tinyworld/core/service.lua
-- skynet 服务基础组件。
-- 约定: 服务启动先创建服务, 再调用该服务的 init 方法。
-- 提供统一 dispatch 分发与 call/return 辅助。

local skynet = require "skynet"
local log = require "tinyworld.core.log"
local M = {}

-- 服务顶层启动: 每个服务文件暴露 cmd 表, 由框架统一 start
function M.startService(serviceName, initFn, cmd)
    skynet.start(function()
        log.setPrefix(serviceName)
        skynet.dispatch("lua", function(_, _, command, ...)
            log.debug("dispatch command %s in %s", command, serviceName)
            local fn = cmd and cmd[command]
            if not fn then
                log.error("unknown command %s in %s", command, serviceName)
                return
            end
            local result = { fn(...) }
            skynet.retpack(table.unpack(result))
        end)

        if initFn then
            local ok, err = pcall(initFn)
            if not ok then
                log.fatal("service init fail: %s", tostring(err))
                skynet.exit()
                return
            end
        end
        log.info("service started")
    end)
end

-- 便捷注册命令名, 自动转成小写下划线
function M.lowercaseName(camel)
    return (camel:gsub("%f[%a]%u", function(c) return "_" .. c:lower() end)
               :gsub("^_", ""))
end

M.skynet = skynet
return M
