-- game/def/container/bag_def.lua
-- 背包容器定义: 背包属于 player, 自身可同步。

local itemDef = require "game.def.container.item_def"

return {
    name = "bag",
    persist = true,
    viewProps = {
        { name = "capacity", type = "number", sync = "all", default = 32 },
    },
    childDef = itemDef,
}
