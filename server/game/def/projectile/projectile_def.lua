-- game/def/projectile/projectile_def.lua
-- 通用战斗实体定义(类型名沿用 Projectile)。
-- 通过 cellComponents 装配 tinyworld.combat.projectile 组件:
--   movement: "none" / "linear" / "homing" / "wander"
--   lifecycle: duration / range
--   behavior: onHit / onIntervalThink / selectTarget / onDestroy(经 spawn runtime 传入)
-- migratable=false: 短生命周期对象不做跨 cell 迁移, tick 始终由创建时的 cell 驱动;
-- 但保持 ghost 同步给其他 cell 的观察者。

return {
    name = "Projectile",
    migratable = false,
    tags = { "projectile", "not_targetable" },
    props = {
        { name = "x", type = "number", sync = "all", persist = true },
        { name = "y", type = "number", sync = "all", persist = true },
        { name = "dir", type = "number", sync = "all", default = 0 },
        { name = "speed", type = "number", sync = "all", default = 10 },
        { name = "range", type = "number", sync = "all", default = 20 },
        { name = "hitRadius", type = "number", sync = "all", default = 2 },
        { name = "ownerId", type = "number", sync = "all" },
        { name = "targetId", type = "number", sync = "all" },

        -- 生命周期
        { name = "duration", type = "number", sync = "all" },
        -- 周期行为
        { name = "tickInterval", type = "number", sync = "all" },
        { name = "areaRadius", type = "number", sync = "all" },
    },
    records = {},
    containers = {},
    cellComponents = {
        "tinyworld.combat.projectile",
    },
    cellOpenViews = {},
}
