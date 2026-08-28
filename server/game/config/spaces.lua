-- game/config/spaces.lua
-- space 配置库: 只描述空间几何与感知参数, 不描述 cellapp 归属。
-- cell 切分支持:
--   * 自动: cellSize(等边长切分) 或 cellCols/cellRows(等行列切分)
--   * 手动: cells = { {id, x, y, w, h}, ... }
-- cellapp 由 world 在 create_space 时运行时分配。
-- 约束: ghostRange 必须大于 aoiRange, 否则跨 cell 的可见性无法保证。

return {
    spaces = {
        {
            id = "main",
            width = 200,
            height = 200,
            aoiRange = 40,
            ghostRange = 48,
            cellSize = 50,
            minMigrateInterval = 0.5,
            hysteresis = 8,
            balance = { enabled = true, strategy = 2 },
        },
        {
            id = "dungeon_1001",
            width = 400,
            height = 400,
            aoiRange = 50,
            ghostRange = 60,
            cells = {
                { id = "a", x = 0, y = 0, w = 200, h = 400 },
                { id = "b", x = 200, y = 0, w = 200, h = 400 },
            },
        },
    },
}
