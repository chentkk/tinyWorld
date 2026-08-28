-- game/def/container/abilities_view_def.lua
-- abilities_view 容器定义: 引用 ability 子对象定义, 且只同步自己。

local abilityDef = require "game.def.ability.ability_def"

return {
    name = "abilities_view",
    persist = false,
    selfOnly = true,
    props = {},
    childDef = abilityDef,
}
