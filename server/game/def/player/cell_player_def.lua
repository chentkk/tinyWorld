-- game/def/player/cell_player_def.lua
-- cell 上的玩家定义: 地图属性 + 战斗状态视图。

local modifiersView = require "game.def.modifier.modifier_view_def"
local abilitiesView = require "game.def.ability.ability_view_def"

return {
    name = "Player",
    props = {
        { include = "game.def.player.attrs" },
        { include = "game.def.player.cell_attrs" },
    },
    records = {},
    containers = {
        modifiersView,
        abilitiesView,
    },
}
