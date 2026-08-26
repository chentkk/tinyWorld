-- game/def/cell_player_def.lua
-- cell 上的实体定义: 只关心地图侧属性, 表格 / 容器为空。
-- 通过 include 复用同一份属性定义, 保证 baseapp 与 cellapp 属性一致。

return {
    name = "Player",
    props = {
        { include = "game.def.attrs" },
        { include = "game.def.cell_attrs" },
    },
    records = {},
    containers = {},
}
