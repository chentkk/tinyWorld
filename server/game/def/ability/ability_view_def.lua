-- game/def/ability/ability_view_def.lua
-- ability 容器子对象定义: 仅同步自己(selfOnly)。

return {
    name = "abilities_view",
    persist = false,
    selfOnly = true,
    viewProps = {},
    childProps = {
        { name = "id", type = "string" },
        { name = "level", type = "number", sync = "all", default = 1 },
        { name = "cooldownLeft", type = "number", sync = "all", default = 0 },
        { name = "state", type = "string", sync = "all", default = "ready" },
    },
}
