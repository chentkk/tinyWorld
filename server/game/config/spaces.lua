-- game/config/spaces.lua
-- 空间配置: cell 划分策略可在此分配, 也可自动按网格划分。
-- balance.enabled / strategy: 只有策略 2(动态 cell 边界)与 3(开关)启用。

return {
    defaultCellApps = { 1, 2 },
    spaces = {
        {
            id = "main",
            width = 200,
            height = 200,
            cellSize = 100,
            aoiRange = 60,
            minMigrateInterval = 1.0,
            hysteresis = 8,
            balance = { enabled = true, strategy = 2 },
        },
    },
}
