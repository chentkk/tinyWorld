-- tinyworld/app/login.lua
-- login 服务: 开启 http 服务, 从 db 校验账户, 通过后下发 token。
-- 之后的登录流程由 gate 接管, gate 调用 auth_token 校验。

local skynet = require "skynet"
local socket = require "skynet.socket"
local service = require "tinyworld.core.service"
local log = require "tinyworld.core.log"
local util = require "tinyworld.core.util"
local proto = require "tinyworld.core.proto"

local cmd = {}
local dbmgr
local tokens = {}

local function dbQuery(sql)
    return skynet.call(dbmgr, "lua", "query", sql)
end

local function queryAccountByName(name)
    local rows = dbQuery(string.format("SELECT * FROM accounts WHERE name='%s'", name))
    return rows and rows[1]
end

local function issueToken(accountId)
    local token = tostring(accountId) .. util.randHex(8)
    tokens[token] = { accountId = accountId, expire = os.time() + 3600 }
    return token
end

function cmd.auth_token(token)
    local info = tokens[token]
    if not info then return nil end
    if info.expire < os.time() then
        tokens[token] = nil
        return nil
    end
    return info.accountId
end

local function login(name, password)
    local account = queryAccountByName(name)
    if not account then return { code = 1, msg = "account not found" } end
    if account.password and account.password ~= password then
        return { code = 2, msg = "password wrong" }
    end
    local accountId = tonumber(account.id) or account.id
    return { code = 0, token = issueToken(accountId), accountId = accountId }
end

function cmd.init(registryAddr)
    dbmgr = skynet.call(registryAddr, "lua", "query", "dbmgr")
    assert(dbmgr, "dbmgr not registered")

    skynet.call(registryAddr, "lua", "register", "login", skynet.self())

    local httpd = require "http.httpd"
    local urllib = require "http.url"
    local sockethelper = require "http.sockethelper"

    local port = tonumber(skynet.getenv("login_port")) or 8080
    local listenFd = socket.listen("0.0.0.0", port)

    socket.start(listenFd, function(fd, addr)
        log.info("login accept fd=%s addr=%s", tostring(fd), addr)
        socket.start(fd)
        local read = sockethelper.readfunc(fd)
        local write = sockethelper.writefunc(fd)

        local code, url, method, header, body = httpd.read_request(read, 8192)
        log.info("login read_request code=%s url=%s", tostring(code), tostring(url))
        if not code then
            socket.close(fd)
            return
        end

        local path, query = urllib.parse(url)
        log.info("login parse ok path=%s", tostring(path))
        local params = query and urllib.parse_query(query) or {}
        log.info("login params name=%s", tostring(params.name))
        local result = login(params.name or "", params.password or "")
        log.info("login handled code=%s", tostring(result and result.code))
        httpd.write_response(write, 200, proto.encode(result))
        log.info("login resp sent %s", proto.encode(result))
        socket.close(fd)
    end)

    log.info("login http listening on %d", port)
end

service.startService("login", nil, cmd)
