-- game/def/container/equipment_def.lua
-- 装备栏容器定义。

return {
    name = "equipment",
    persist = true,
    viewProps = {},
    childProps = {
        { name = "id", type = "number" },
        { name = "slotName", type = "number", sync = "all" },
        { name = "itemId", type = "number", sync = "all" },
    },
}
