-- game/def/player/player_def.lua
-- 玩家定义: 属性 + 任务表格 + 背包/装备容器。
-- 表格/容器定义引用各自的 def 目录。

local bagDef = require "game.def.container.bag_def"
local equipmentDef = require "game.def.container.equipment_def"

return {
    name = "Player",
    props = {
        { include = "game.def.player.attrs" },
        { include = "game.def.player.cell_attrs" },
    },
    records = {
        {
            name = "current_tasks", sync = "all", keyFields = { "taskid" },
            fields = {
                { name = "taskid", type = "number", sync = "all" },
                { name = "state", type = "number", sync = "all", default = 0 },
                { name = "progress", type = "number", sync = "all", default = 0 },
            },
        },
        {
            name = "completed_tasks", sync = "none", keyFields = { "taskid" },
            fields = {
                { name = "taskid", type = "number" },
            },
        },
        {
            name = "abilities", sync = "none", keyFields = { "name" },
            fields = {
                { name = "name", type = "string" },
            },
        },
    },
    containers = {
        bagDef,
        equipmentDef,
    },
}
