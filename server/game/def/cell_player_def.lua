-- game/def/cell_player_def.lua
-- cell 上的实体定义: 地图侧属性 + 战斗状态视图。
-- modifiers_view 观察者可看; abilities_view 仅同步自己。

return {
    name = "Player",
    props = {
        { include = "game.def.attrs" },
        { include = "game.def.cell_attrs" },
    },
    records = {},
    containers = {
        {
            name = "modifiers_view", persist = false,
            viewProps = {},
            childProps = {
                { name = "id", type = "number" },
                { name = "name", type = "string", sync = "all" },
                { name = "stack", type = "number", sync = "all", default = 1 },
                { name = "duration", type = "number", sync = "all", default = 0 },
                { name = "remaining", type = "number", sync = "all", default = 0 },
            },
        },
        {
            name = "abilities_view", persist = false, selfOnly = true,
            viewProps = {},
            childProps = {
                { name = "id", type = "string" },
                { name = "level", type = "number", sync = "all", default = 1 },
                { name = "cooldownLeft", type = "number", sync = "all", default = 0 },
                { name = "state", type = "string", sync = "all", default = "ready" },
            },
        },
    },
}
