-- game/def/player_def.lua
-- 玩家定义: 属性 + 表格(任务) + 容器(背包、装备栏)。

return {
    name = "Player",
    props = {
        { include = "game.def.attrs" },
        { include = "game.def.cell_attrs" },
    },
    records = {
        {
            name = "current_tasks", sync = "all", keyFields = { "taskid" },
            fields = {
                { name = "taskid", type = "number", sync = "all", comment = "任务id" },
                { name = "state", type = "number", sync = "all", default = 0 },
                { name = "progress", type = "number", sync = "all", default = 0 },
            },
        },
        {
            name = "completed_tasks", sync = "none", keyFields = { "taskid" },
            fields = {
                { name = "taskid", type = "number", comment = "任务id" },
            },
        },
    },
    containers = {
        {
            name = "bag", persist = true,
            viewProps = {
                { name = "capacity", type = "number", sync = "all", default = 32 },
            },
            childProps = {
                { name = "id", type = "number", comment = "唯一id" },
                { name = "slot", type = "number", sync = "all", comment = "格子" },
                { name = "itemId", type = "number", sync = "all", comment = "道具id" },
                { name = "count", type = "number", sync = "all", default = 1 },
            },
        },
        {
            name = "equipment", persist = true,
            viewProps = {},
            childProps = {
                { name = "id", type = "number", comment = "唯一id" },
                { name = "slotName", type = "number", sync = "all", comment = "装备位" },
                { name = "itemId", type = "number", sync = "all", comment = "道具id" },
            },
        },
    },
}
