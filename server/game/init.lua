-- game/init.lua
-- 游戏侧挂载点: 注册对象定义、加载 / 保存玩家数据、
-- 组装 baseentity / cellentity 组件。框架通过这些钩子感知
-- 不同对象使用了哪些组件与定义。

local defs = require "tinyworld.entity.defs"
local bin = require "tinyworld.core.bin"
local M = {}

function M.registerDefs()
    defs.register("Player", "game.def.player_def")
end

function M.registerCellDefs()
    defs.register("Player", "game.def.cell_player_def")
end

local function findDb()
    local skynet = require "skynet"
    return skynet.getenv("addr_dbmgr")
end

function M.loadPlayer(playerId)
    local skynet = require "skynet"
    local data = {
        props = { id = playerId },
        records = {},
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
        if loaded then return loaded end
    end
    return data
end

function M.savePlayer(playerId, dump)
    local body = bin.packEntity(dump)
    if not findDb() then return end
    local skynet = require "skynet"
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

-- baseapp 侧组件的装配: 框架借此知道玩家使用了哪些组件
function M.setupBaseEntity(entity)
    local comp = require "game.components.bag"
    entity:addComponent("bag", comp.Bag)
    entity:addComponent("equipment", require("game.components.equipment").Equipment)
    entity:addComponent("task", require("game.components.task").Task)

    local bag = entity:getContainer("bag")
    if bag then bag:openView("bag") end
    local equipment = entity:getContainer("equipment")
    if equipment then equipment:openView("equipment") end
end

-- cellapp 侧组件的装配
function M.setupCellEntity(real, data)
    local moveComp = require "game.components.move"
    real:addComponent("move", moveComp.Move)

    -- 战斗一次性事件(伤害/治疗/modifier) -> 客户端 rpc 广播(自己 + 周围玩家)
    local combatSync = require "tinyworld.combat.sync"
    real:addComponent("combat_sync", combatSync.CombatSync)

    -- 客户端释放技能与战斗驱动
    local combatAgent = require "game.components.combat_agent"
    real:addComponent("combat_agent", combatAgent.CombatAgent)
end

return M
