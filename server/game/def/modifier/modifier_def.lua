-- game/def/modifier/modifier_def.lua
-- modifier 对象定义: 结构同 player / monster 的 def, 使用 props。

return {
    name = "modifier",
    props = {
        { name = "id", type = "number" },
        { name = "name", type = "string", sync = "all" },
        { name = "stack", type = "number", sync = "all", default = 1 },
        { name = "duration", type = "number", sync = "all", default = 0 },
        { name = "remaining", type = "number", sync = "all", default = 0 },
    },
    records = {},
}
