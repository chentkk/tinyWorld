-- game/player/player_data.lua
-- 玩家数据的 db 读取 / 打包 / 保存。纯数据访问, 不包含实体装配逻辑。

local bin = require "tinyworld.core.bin"
local M = {}

local dbAddr

function M.setDbAddr(addr)
    dbAddr = addr
end

local function findDb()
    return dbAddr
end

function M.load(playerId)
    local skynet = require "skynet"
    local data = {
        props = { id = playerId },
        records = {
            abilities = {
                { name = "ability_aphotic_shield" },
                { name = "ability_borrowed_time" },
                { name = "ability_mist_coil" },
                { name = "ability_blood_harvest" },
            },
        },
        containers = {},
    }

    -- 基础行数据作为默认属性
    local rows = skynet.call(findDb(), "lua", "query",
        string.format("SELECT * FROM players WHERE id=%d", playerId))
    if rows and rows[1] then
        local row = rows[1]
        data.props.id = playerId
        data.props.name = row.name or ""
        data.props.level = tonumber(row.level) or 1
        data.props.hp = tonumber(row.hp) or 100
        data.props.maxHp = tonumber(row.max_hp) or 100
        data.props.mp = tonumber(row.mp) or 100
        data.props.maxMp = tonumber(row.max_mp) or 100
        data.props.gold = tonumber(row.gold) or 0
        data.props.scene = row.scene or "main"
        data.props.x = tonumber(row.x) or 10
        data.props.y = tonumber(row.y) or 10
    end

    local rows = skynet.call(findDb(), "lua", "query",
        string.format("SELECT * FROM player_bin WHERE player_id=%d", playerId))
    local row = rows and rows[1]
    if row and row.bin and row.bin ~= "" then
        local loaded = bin.unpackEntity(row.bin)
        if loaded then
            loaded.records = loaded.records or {}
            -- 旧档可能缺少新增字段, 这里做最小数据补齐
            if not loaded.records.abilities then
                loaded.records.abilities = data.records.abilities
            end
            return loaded
        end
    end
    return data
end

function M.save(playerId, dump)
    local skynet = require "skynet"
    local body = bin.packEntity(dump)
    if not findDb() then return end

    local rows = skynet.call(findDb(), "lua", "query",
        string.format("SELECT player_id FROM player_bin WHERE player_id=%d", playerId))
    if rows and rows[1] then
        skynet.call(findDb(), "lua", "exec",
            string.format("UPDATE player_bin SET bin='%s' WHERE player_id=%d", body, playerId))
    else
        skynet.call(findDb(), "lua", "exec",
            string.format("INSERT INTO player_bin (player_id,bin) VALUES (%d,'%s')", playerId, body))
    end
end

-- cell 初始化数据: baseapp 从玩家数据中提取, 交给 cell 创建对象时使用。
function M.buildCellData(entity)
    local abilities = {}
    for _, row in ipairs(entity:getRecord("abilities"):rowsList()) do
        abilities[#abilities + 1] = row.name
    end
    return { abilities = abilities }
end

return M
