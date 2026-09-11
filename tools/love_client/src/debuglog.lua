-- client/src/debuglog.lua
-- 客户端调试日志: 无人值守跑 client 时, 写入 logs/client_debug.log。

local M = {}

function M.write(fmt, ...)
    local f = io.open("logs/client_debug.log", "a")
    if not f then return end
    f:write(string.format("[%s] ", os.date("%Y-%m-%d %H:%M:%S")))
    f:write(string.format(fmt or "", ...))
    f:write("\n")
    f:close()
end

return M
