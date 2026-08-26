-- tinyworld/app/db.lua
-- 通用 db 服务: 执行 sql 语句。可配置运行多个实例做负载均衡。
-- 环境变量 db_mode = "mock" 时使用内存库, 便于无 mysql 环境测试。

local skynet = require "skynet"
local service = require "tinyworld.core.service"
local log = require "tinyworld.core.log"

local mysql
local mockdb
local mode = skynet.getenv("db_mode") or "mock"

local cmd = {}

function cmd.query(sql)
    if not mysql then return nil, "db not ready" end
    if mode == "mock" then return mockdb.query(sql) end
    return mysql:query(sql)
end

function cmd.exec(sql)
    if not mysql then return nil, "db not ready" end
    if mode == "mock" then return mockdb.exec(sql) end
    return mysql:query(sql)
end

local function init()
    if mode == "mock" then
        mockdb = require "tinyworld.core.mockdb"
        mysql = mockdb
        log.info("db mode=mock")
        return
    end

    local dbconf = {
        host = skynet.getenv("db_host") or "127.0.0.1",
        port = tonumber(skynet.getenv("db_port")) or 3306,
        user = skynet.getenv("db_user") or "root",
        password = skynet.getenv("db_password") or "",
        database = skynet.getenv("db_database") or "tinyworld",
        max_packet_size = 1024 * 1024,
        charset = "utf8mb4",
    }
    mysql = require "skynet.db.mysql"
    mysql = mysql.connect(dbconf)
    log.info("db connected %s:%d", dbconf.host, dbconf.port)
end

service.startService("db", init, cmd)
