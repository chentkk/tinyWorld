-- game/def/container/item_def.lua
-- 背包/装备子对象定义: 与 player/modifier 相同结构, 使用 props。

return {
    name = "item",
    props = {
        { name = "id", type = "number" },
        { name = "slot", type = "number", sync = "all" },
        { name = "itemId", type = "number", sync = "all" },
        { name = "count", type = "number", sync = "all", default = 1 },
    },
    records = {},
}
