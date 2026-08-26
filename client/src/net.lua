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
local function packU16(n)
    return string.char(math.floor(n / 256) % 256, n % 256)
end

local function unpackU16(s)
    return string.byte(s, 1) * 256 + string.byte(s, 2)
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
    sock:settimeout(0) -- 之后读取 non-blocking, 避免阻塞 game loop
    return true
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

    -- 小包用短暂阻塞发送, 避免 non-blocking 下数据未发完
    sock:settimeout(0.5)
    local sent, sendErr = sock:send(header .. body)
    sock:settimeout(0)

    if sent ~= #header + #body then
        local dbg = require "src.debuglog"
        dbg.write("send FAIL sent=%s err=%s", tostring(sent), tostring(sendErr))
    end

    writeLog("send", t.t, t.n, json.encode(t.d or {}))
end

function M.enqueue(t, n, d)
    M.sendFrame({ t = t, n = n, d = d or {} })
end

function M.update()
    if not sock then return end

    local chunk, err = sock:receive()
    while chunk do
        buffer = buffer .. chunk
        while true do
            if #buffer < 2 then break end
            local len = unpackU16(buffer)
            if #buffer < 2 + len then break end
            local body = buffer:sub(3, 2 + len)
            buffer = buffer:sub(3 + len)
            local msg = json.decode(body)
            if msg then
                if msg.t == "AUTH" and msg.n == "auth_ok" and msg.d and msg.d.connId then
                    M.connId = msg.d.connId
                end
                writeLog("recv", msg.t, msg.n, json.encode(msg.d or {}))
                if M.onMessage then M.onMessage(msg) end
            end
        end
        chunk = sock:receive()
    end
end

return M
