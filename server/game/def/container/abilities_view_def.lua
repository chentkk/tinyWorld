-- game/def/container/abilities_view_def.lua
-- abilities_view 容器定义: 引用 ability 子对象定义, 仅同步玩家自己。

local abilityDef = require "game.def.ability.ability_def"

return {
    name = "abilities_view",
    persist = false,
    sync = "self",
    props = {},
    childDef = abilityDef,
}
