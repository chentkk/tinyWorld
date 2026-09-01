-- game/def/player/cell_player_def.lua
-- cell 上的玩家定义: 地图属性 + 战斗状态视图容器。

local modifiersViewDef = require "game.def.container.modifiers_view_def"
local abilitiesViewDef = require "game.def.container.abilities_view_def"

return {
    name = "Player",
    props = {
        { include = "game.def.player.attrs" },
        { include = "game.def.player.cell_attrs" },
    },
    records = {},
    containers = {
        modifiersViewDef,
        abilitiesViewDef,
    },
    cellComponents = {
        "game.components.move",
        { name = "combat_sync", module = "tinyworld.app.cellapp.sync" },
        "game.components.combat_agent",
        { name = "combat_settlement", module = "tinyworld.app.cellapp.settlement" },
        { name = "cell_sync_stress", module = "game.components.sync_stress" },
    },
    cellOpenViews = { "modifiers_view", "abilities_view" },
}
