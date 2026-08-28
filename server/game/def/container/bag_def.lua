-- game/def/container/bag_def.lua
-- 背包容器定义: 背包属于 player, 自身可同步。

return {
    name = "bag",
    persist = true,
    viewProps = {
        { name = "capacity", type = "number", sync = "all", default = 32 },
    },
    childProps = {
        { name = "id", type = "number" },
        { name = "slot", type = "number", sync = "all" },
        { name = "itemId", type = "number", sync = "all" },
        { name = "count", type = "number", sync = "all", default = 1 },
    },
}
