-- game/config/entity_defs.lua
-- 框架服务通过本清单注册实体定义(business 以纯配置形式提供信息)。
-- base: baseapp 侧实体定义与额外 boot 模块
-- cell: cellapp 侧实体定义与额外 boot 模块

return {
    base = {
        boot = {},
        defs = {
            { kind = "Player", module = "game.def.player.player_def" },
        },
    },
    cell = {
        boot = {
            "game.scripts.vscripts.abilities",
        },
        defs = {
            { kind = "Player", module = "game.def.player.cell_player_def" },
            { kind = "Projectile", module = "game.def.projectile.projectile_def" },
        },
    },
}
