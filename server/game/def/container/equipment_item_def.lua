-- game/def/container/equipment_item_def.lua
-- 装备栏子对象定义。

return {
    name = "equipment_item",
    props = {
        { name = "id", type = "number" },
        { name = "slotName", type = "number", sync = "all" },
        { name = "itemId", type = "number", sync = "all" },
    },
    records = {},
}
