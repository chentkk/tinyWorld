-- game/def/modifier/modifier_view_def.lua
-- modifier 容器子对象定义: 观察者可看; key 使用独立唯一 id, 同名 modifier 可多个。

return {
    name = "modifiers_view",
    persist = false,
    viewProps = {},
    childProps = {
        { name = "id", type = "number" },
        { name = "name", type = "string", sync = "all" },
        { name = "stack", type = "number", sync = "all", default = 1 },
        { name = "duration", type = "number", sync = "all", default = 0 },
        { name = "remaining", type = "number", sync = "all", default = 0 },
    },
}
