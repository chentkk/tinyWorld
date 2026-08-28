-- game/def/container/equipment_def.lua
-- 装备栏容器定义。

local equipmentItemDef = require "game.def.container.equipment_item_def"

return {
    name = "equipment",
    persist = true,
    viewProps = {},
    childDef = equipmentItemDef,
}
