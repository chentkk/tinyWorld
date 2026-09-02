-- game/def/projectile/projectile_def.lua
-- 投掷物定义。位置/运动/命中判定由 framework spawn 与 game 组件处理,
-- 命中效果通过 projectile_hit 事件交给游戏层结算, 不在此固定伤害字段。
-- migratable=false: 投掷物为短生命周期对象, 不做跨 cell 迁移(始终由创建时的
-- cell 驱动 tick); 但不关闭 ghost, 其他 cell 仍会创建 ghost 并收到位置同步。

return {
    name = "Projectile",
    migratable = false,
    props = {
        { name = "x", type = "number", sync = "all", persist = true },
        { name = "y", type = "number", sync = "all", persist = true },
        { name = "dir", type = "number", sync = "all", default = 0 },
        { name = "speed", type = "number", sync = "all", default = 10 },
        { name = "range", type = "number", sync = "all", default = 20 },
        { name = "hitRadius", type = "number", sync = "all", default = 2 },
        { name = "ownerId", type = "number", sync = "all" },
        { name = "targetId", type = "number", sync = "all" },
        { name = "pierce", type = "boolean", sync = "all", default = false },
        { name = "maxHits", type = "number", sync = "all" },
    },
    records = {},
    containers = {},
    cellComponents = {
        "tinyworld.combat.projectile",
    },
    cellOpenViews = {},
}
