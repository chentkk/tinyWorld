-- client/src/net.lua
-- 客户端网络: 连接、帧收发、登录与角色选择流程。

local json = require "src.json"
local socket = require "socket"
local M = {}

M.connId = nil
M.selfId = nil
M.onMessage = nil
M.logFile = nil

local sock
local buffer = ""

-- LÖVE 11.x 使用 LuaJIT(5.1), 没有 string.pack/unpack
-- 与服务器 proto.lua 一致: 2 字节小端长度
local function packU16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end

local function unpackU16(s)
    return string.byte(s, 1) + string.byte(s, 2) * 256
end

local function writeLog(kind, msgType, name, data)
    if not M.logFile then
        M.logFile = io.open("logs/message.log", "a")
    end
    if not M.logFile then return end

    local conn = M.connId or "?"
    local line
    if kind == "send" then
        line = string.format("[%s][%s] %s %s %s{%s}\n", os.date("%Y-%m-%d %H:%M:%S"),
            conn, kind, msgType, name or "", data or "")
    else
        line = string.format("[%s][%s] %s %s %s{%s}\n", os.date("%Y-%m-%d %H:%M:%S"),
            conn, kind, msgType, name or "", data or "")
    end
    M.logFile:write(line)
    M.logFile:flush()
end

M.writeLog = writeLog

function M.connect(host, port)
    sock = socket.tcp()
    sock:settimeout(5)
    local ok, err = sock:connect(host, port)
    if not ok then return nil, err end

    -- LÖVE 合并 LuaSocket 时 connect 可能立即返回(non-blocking EINPROGRESS),
    -- 需要 select 等 fd 可写确保连接真正建立。
    for i = 1, 50 do
        local _, writable = socket.select(nil, { sock }, 0.1)
        if writable and #writable > 0 then return true end
    end
    return nil, "connect timeout"
end

function M.login(host, loginPort, name, password)
    local http = require "socket.http"
    local body, code = http.request("http://" .. host .. ":" .. loginPort ..
        "/login?name=" .. name .. "&password=" .. password)
    if code ~= 200 or not body then return nil end
    return json.decode(body)
end

function M.sendFrame(t)
    local body = json.encode(t)
    local header = packU16(#body)

    sock:settimeout(2)
    -- 发送前确保可写(非阻塞 fd 不能直接 send)
    for i = 1, 50 do
        local _, writable = socket.select(nil, { sock }, 0.1)
        if writable and #writable > 0 then break end
        socket.sleep(0.01)
    end

    local sent, sendErr = sock:send(header .. body)

    if sent ~= #header + #body then
        local dbg = require "src.debuglog"
        dbg.write("send FAIL sent=%s err=%s", tostring(sent), tostring(sendErr))
    end

    writeLog("send", t.t, t.n, json.encode(t.d or {}))
end

function M.enqueue(t, n, d)
    M.sendFrame({ t = t, n = n, d = d or {} })
    -- 发送后立即驱动 luasocket flush 一次
    socket.sleep(0.05)
end

function M.update()
    if not sock then return end

    -- LÖVE 11.x 的 LuaSocket 需要 socket.sleep() 驱动底层的 select / 发送缓冲
    socket.sleep(0.02)

    sock:settimeout(0.05)
    -- LuaSocket 默认 receive() 是 *l, 不能读二进制帧, 因此逐字节拼帧
    local byte = sock:receive(1)
    while byte do
        buffer = buffer .. byte
        while true do
            if #buffer < 2 then break end
            local len = unpackU16(buffer)
            if #buffer < 2 + len then break end
            local body = buffer:sub(3, 2 + len)
            buffer = buffer:sub(3 + len)
            local msg = json.decode(body)
            if msg then
                if msg.t == "batch" then
                    -- 服务器把同一 tick 的多条消息合并成一帧; 这里按顺序展开逐条处理
                    for _, sub in ipairs(msg.d.msgs or {}) do
                        writeLog("recv", sub.t, sub.n, json.encode(sub.d or {}))
                        if M.onMessage then M.onMessage(sub) end
                    end
                else
                    if msg.t == "AUTH" and msg.n == "auth_ok" and msg.d and msg.d.connId then
                        M.connId = msg.d.connId
                    end
                    writeLog("recv", msg.t, msg.n, json.encode(msg.d or {}))
                    if M.onMessage then M.onMessage(msg) end
                end
            end
        end
        byte = sock:receive(1)
    end
end

return M
