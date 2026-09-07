-- tinyworld/core/log.lua
-- 彩色分级日志。cellapp / baseapp 等服务可携带自身前缀。

local M = {}

local levels = {
    debug = { 1, "DEBUG", "\27[90m" },
    info  = { 2, "INFO",  "\27[32m" },
    warn  = { 3, "WARN",  "\27[33m" },
    error = { 4, "ERROR", "\27[31m" },
    fatal = { 5, "FATAL", "\27[35m" },
}

local minLevel = 2
local colorOff = false
local prefix = ""

function M.setMinLevel(name)
    minLevel = levels[name] and levels[name][1] or 1
end

function M.setColor(enable)
    colorOff = enable == false
end

function M.setPrefix(text)
    prefix = text
end

local function formatTime()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function write(levelName, fmt, ...)
    local def = levels[levelName]
    if not def then return end
    if def[1] < minLevel then return end

    local msg = string.format(fmt or "", ...)
    local head = string.format("[%s][%s]", formatTime(), prefix)
    if colorOff then
        print(string.format("%s %s %s", head, def[2], msg))
        return
    end
    print(string.format("%s %s%s\27[0m %s", head, def[3], def[2], msg))
end

function M.debug(fmt, ...) write("debug", fmt, ...) end
function M.info(fmt, ...)  write("info",  fmt, ...) end
function M.warn(fmt, ...)  write("warn",  fmt, ...) end
function M.error(fmt, ...) write("error", fmt, ...) end
function M.fatal(fmt, ...) write("fatal", fmt, ...) end

-- 兼容服务调用时可传递 skynet.error 风格的变参
function M.printf(levelName, ...)
    local def = levels[levelName]
    if not def then return end
    if def[1] < minLevel then return end
    local head = string.format("[%s][%s]", formatTime(), prefix)
    print(string.format("%s %s %s", head, def[2], table.concat({...}, " ")))
end

return M
