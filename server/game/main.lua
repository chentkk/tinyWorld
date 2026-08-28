-- game/main.lua
-- 游戏侧启动钩子。框架启动完成所有底层服务后会调用 gameMain.start(registryAddr),
-- 游戏在这里启动自己独有的业务服务; 本钩子在框架 bootstrap 进程内同步执行。

local M = {}

function M.start(registryAddr)
    -- 当前没有额外游戏业务服务, 只保留启动入口。
    -- 未来示例:
    --   local addr = skynet.newservice("myservice")
    --   skynet.call(addr, "lua", "init", registryAddr)
end

return M
