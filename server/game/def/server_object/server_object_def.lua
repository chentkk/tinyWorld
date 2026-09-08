-- game/def/server_object/server_object_def.lua
-- 纯服务器对象(触发器/刷怪器/活动宿主)。
-- networked=false: 完全不进入客户端同步链路。
-- migratable=false: 目前固定由创建时 cell 持有, 不参与迁移。

return {
    name = "ServerObject",
    networked = false,
    migratable = false,
    tags = { "server_object", "not_targetable" },
    props = {
        { name = "x", type = "number", sync = "none", persist = true },
        { name = "y", type = "number", sync = "none", persist = true },
        { name = "radius", type = "number", sync = "none" },
        { name = "duration", type = "number", sync = "none" },
        { name = "tickInterval", type = "number", sync = "none" },
        { name = "ownerId", type = "number", sync = "none" },
    },
    records = {},
    containers = {},
    cellComponents = {
        "tinyworld.app.cellapp.components.server_object",
    },
    cellOpenViews = {},
}
