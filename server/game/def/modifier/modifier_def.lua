-- game/def/modifier/modifier_def.lua
-- modifier 对象定义: 结构同 player / monster 的 def, 使用 props。
-- modifier 只保存纯状态(不持有 ability / caster 对象), 因此来源信息(casterId /
-- abilityName)与运行期派生量(intervalThink / elapsed)都必须可序列化, 供迁移重建。

return {
    name = "modifier",
    props = {
        { name = "id", type = "number" },
        { name = "name", type = "string", sync = "all" },
        { name = "stack", type = "number", sync = "all", default = 1 },
        { name = "duration", type = "number", sync = "all", default = 0 },
        { name = "remaining", type = "number", sync = "all", default = 0 },
        -- 迁移重建用纯状态: 仅服务器持有, 不下发客户端
        { name = "abilityName", type = "string", sync = "none" },
        { name = "casterId", type = "number", sync = "none" },
        { name = "intervalThink", type = "number", sync = "none", default = 0 },
        { name = "elapsed", type = "number", sync = "none", default = 0 },
    },
    records = {},
    class = "tinyworld.combat.modifier",
}
