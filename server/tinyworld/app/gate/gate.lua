-- tinyworld/app/gate.lua
-- 网关服务(可运行多个, 支持负载均衡)。
-- 负责客户端连接管理(连接/断开/消息), AUTH 校验通过后把客户端消息
-- 转发给绑定的 baseapp。gate 不注册具体业务 rpc。
-- 收发消息都调用 logservice 写入 message.log, 便于调试。

local skynet = require "skynet"
local socket = require "skynet.socket"
local service = require "tinyworld.core.service"
local log = require "tinyworld.core.log"
local proto = require "tinyworld.core.proto"
local msgUtil = require "tinyworld.net.msg"
local protocol = require "tinyworld.net.protocol"

local cmd = {}
local conns = {} -- fd -> conn
local byConnId = {}
local connSeq = 0
local gateId = 1
local baseApps = {}
local baseAppCount = 1
local seqRound = 0
local logAddr
local loginAddr

local function writeLog(connId, kind, msgType, name, data)
    pcall(skynet.send, logAddr, "lua", "write", connId, kind, msgType, name, data or "")
end

local function pickBaseApp()
    seqRound = seqRound + 1
    return baseApps[((seqRound - 1) % baseAppCount) + 1]
end

local function closeConn(conn)
    if not conn or not conns[conn.fd] then return end
    byConnId[conn.connId] = nil
    conns[conn.fd] = nil
    socket.close(conn.fd)
    writeLog(conn.connId, "", "", "", conn.addr .. " disconnect.")
    if conn.baseApp then
        pcall(skynet.send, conn.baseApp, "lua", "client_disconnect", conn.connId)
    end
end

local function sendBody(conn, msgType, name, dataStr, body)
    local ok = pcall(socket.write, conn.fd, proto.packBody(body))
    if not ok then
        log.warn("sendBody failed connId=%s", conn.connId)
        closeConn(conn)
        return false
    end
    writeLog(conn.connId, "send", msgType, name, dataStr)
    return true
end

function cmd.send_to_client(connId, body, msgType, name, dataStr)
    local conn = byConnId[connId]
    if not conn then return false end

    local msg = proto.decode(body)
    msgType = msgType or (msg and msg.t) or "?"
    name = name or (msg and msg.n) or ""
    dataStr = dataStr or msgUtil.logData(msg and msg.d, msg and msg.t, msg and msg.n)
    sendBody(conn, msgType, name, dataStr, body)
    return true
end

function cmd.kick(connId)
    closeConn(byConnId[connId])
end

local function handleAuth(conn, msg)
    writeLog(conn.connId, "recv", "AUTH", "auth", msgUtil.logData(msg.d, msg.t, msg.n))

    local accountId = skynet.call(loginAddr, "lua", "auth_token", msg.d.token)
    if not accountId then
        sendBody(conn, "AUTH", "auth_fail", "code=1 msg=bad token",
            proto.encode(protocol.authFail(1, "bad token")))
        closeConn(conn)
        return
    end

    conn.accountId = accountId
    conn.baseApp = pickBaseApp()
    skynet.send(conn.baseApp, "lua", "open_client", conn.gateway, conn.fd, conn.connId, accountId)

    local reply = protocol.authOk(accountId, conn.connId)
    sendBody(conn, "AUTH", "auth_ok", msgUtil.logData(reply.d, reply.t, reply.n), proto.encode(reply))
end

local function onClientData(conn, body)
    local msg = proto.decode(body)
    if not msg or not msg.t then return end

    if msg.t == "AUTH" then
        handleAuth(conn, msg)
        return
    end

    writeLog(conn.connId, "recv", msg.t, msg.n, msgUtil.logData(msg.d, msg.t, msg.n))
    if conn.baseApp then
        skynet.send(conn.baseApp, "lua", "client_data", conn.connId, body)
    end
end

local function reader(conn)
    local fd = conn.fd
    local ok = pcall(function()
        while conns[fd] do
            local header = socket.read(fd, 2)
            if not header then return end

            local len = string.unpack("<I2", header)
            local body = socket.read(fd, len)
            if not body then return end

            onClientData(conn, body)
        end
    end)
    if not ok then
        log.warn("client reader error connId=%s", conn.connId)
    end
    closeConn(conn)
end

function cmd.init(registryAddr, port, id)
    gateId = id or 1

    logAddr = skynet.call(registryAddr, "lua", "query", "log")
    loginAddr = skynet.call(registryAddr, "lua", "query", "login")
    assert(logAddr, "log not registered")
    assert(loginAddr, "login not registered")

    baseAppCount = tonumber(skynet.getenv("baseapp_count")) or 1
    for i = 1, baseAppCount do
        baseApps[i] = skynet.call(registryAddr, "lua", "query", "baseapp." .. i)
        assert(baseApps[i], "baseapp." .. i .. " not registered")
    end

    skynet.call(registryAddr, "lua", "register", "gate." .. gateId, skynet.self())

    port = tonumber(port) or 8000
    local listenFd = socket.listen("0.0.0.0", port)
    socket.start(listenFd, function(fd, addr)
        socket.start(fd)
        connSeq = connSeq + 1

        local conn = {
            fd = fd,
            connId = string.format("%d-%d", gateId, connSeq),
            addr = addr,
            gateway = skynet.self(),
        }
        conns[fd] = conn
        byConnId[conn.connId] = conn
        writeLog(conn.connId, "", "", "", addr .. " connect.")
        log.info("client connect %s %s", conn.connId, addr)

        skynet.fork(reader, conn)
    end)

    log.info("gate %d listening on %d", gateId, port)
end


service.startService("gate", nil, cmd)
return cmd
