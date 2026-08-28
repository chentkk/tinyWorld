-- game/config/init.lua
-- 游戏配置聚合入口。框架 boot 只读取这一个模块,
-- 各框架服务通过 init 参数接收配置, 不再各自 require game.config.*。

return {
    spaces = require "game.config.spaces",
    entityDefs = require "game.config.entity_defs",
    schema = require "game.config.schema",
    playerStore = {
        playerTable = "players",
        binTable = "player_bin",
        accountIdField = "account_id",
        ownerIdField = "player_id",
        binField = "bin",
        template = require "game.config.player_template",
        rowProps = {
            name = "name",
            level = "level",
            hp = "hp",
            maxHp = "max_hp",
            mp = "mp",
            maxMp = "max_mp",
            gold = "gold",
            scene = "scene",
            x = "x",
            y = "y",
        },
        createDefaults = {
            level = 1,
            hp = 100,
            max_hp = 100,
            mp = 100,
            max_mp = 100,
            gold = 0,
            scene = "main",
            x = 10,
            y = 10,
        },
        cellData = {
            { target = "abilities", record = "abilities", field = "name" },
        },
    },
}
