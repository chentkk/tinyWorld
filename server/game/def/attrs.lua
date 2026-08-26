-- game/def/attrs.lua
-- 玩家基础属性定义(可被其他属性定义文件 include 复用)。

return {
    props = {
        { name = "id", type = "number", sync = "all", persist = true, comment = "玩家id" },
        { name = "name", type = "string", sync = "all", persist = true, comment = "名称", default = "" },
        { name = "level", type = "number", sync = "all", persist = true, comment = "等级", default = 1 },
        { name = "hp", type = "number", sync = "all", persist = true, comment = "血量", default = 100 },
        { name = "maxHp", type = "number", sync = "all", persist = true, comment = "最大血量", default = 100 },
        { name = "mp", type = "number", sync = "all", persist = true, comment = "魔法", default = 100 },
        { name = "maxMp", type = "number", sync = "all", persist = true, comment = "最大魔法", default = 100 },
        { name = "gold", type = "number", sync = "all", persist = true, comment = "金币", default = 0 },
        { name = "scene", type = "string", sync = "all", persist = true, comment = "场景", default = "main" },
        { name = "speed", type = "number", sync = "all", persist = true, comment = "移速", default = 6 },
    },
}
