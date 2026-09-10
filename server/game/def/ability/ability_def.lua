-- game/def/ability/ability_def.lua
-- ability 对象定义: 结构同 player, 使用 props。

return {
    name = "ability",
    props = {
        { name = "id", type = "string" },
        { name = "level", type = "number", sync = "all", default = 1 },
        { name = "cooldownLeft", type = "number", sync = "all", default = 0 },
        { name = "state", type = "string", sync = "all", default = "ready" },
    },
    records = {},
    -- 迁移/加载时重建 Ability 实例(否则退化为纯数据 Object, onTick 会崩)
    class = "tinyworld.combat.ability",
}
