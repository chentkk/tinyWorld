-- tinyworld/app/dbmgr.lua
-- db 管理器: 运行多个 db 服务, 按 sql 字符串散列做负载均衡。

local skynet = require "skynet"
local service = require "tinyworld.core.service"
local log = require "tinyworld.core.log"

local cmd = {}
local dbs = {}
local count = 0
local execRound = 0

local function pickDb(sql)
    if #dbs == 1 then return dbs[1] end
    local h = 5381
    for i = 1, #sql do
        h = (h * 33 + string.byte(sql, i)) % 65536
    end
    return dbs[(h % #dbs) + 1]
end

function cmd.query(sql)
    local db = pickDb(sql)
    assert(db, "no db service")
    return skynet.call(db, "lua", "query", sql)
end

function cmd.exec(sql)
    assert(#dbs > 0, "no db service")
    execRound = execRound + 1
    local db = dbs[((execRound - 1) % #dbs) + 1]
    return skynet.call(db, "lua", "exec", sql)
end

local function init()
    count = tonumber(skynet.getenv("db_count")) or 1
    for i = 1, count do
        dbs[i] = skynet.newservice("db")
        log.info("db service %d created", i)
    end

    -- mock 模式下初始化 schema
    if (skynet.getenv("db_mode") or "mock") == "mock" then
        local schema = require "game.config.schema"
        for _, sql in ipairs(schema.mocks or {}) do
            skynet.call(dbs[1], "lua", "exec", sql)
        end
    end
end

service.startService("dbmgr", init, cmd)
