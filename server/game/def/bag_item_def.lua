-- game/def/bag_item_def.lua
-- 背包子对象定义: 容器装载对象也有自己的 *_def 文件, 结构一致。

return {
    childProps = {
        { name = "id", type = "number" },
        { name = "slot", type = "number", sync = "all" },
        { name = "itemId", type = "number", sync = "all" },
        { name = "count", type = "number", sync = "all", default = 1 },
    },
}
