-- game/config/init.lua
-- 游戏配置聚合入口。框架 boot 只读取这一个模块,
-- 各框架服务通过 init 参数接收配置, 不再各自 require game.config.*。

return {
    spaces = require "game.config.spaces",
    entityDefs = require "game.config.entity_defs",
    schema = require "game.config.schema",
}
