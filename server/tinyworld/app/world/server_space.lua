-- tinyworld/app/world/server_space.lua
-- world 服务侧的完整 space 信息(相当于 bigworld 的 cell 管理器视图)。
-- config 由 world 在创建 space 时编译完成, 已经包含运行时 cellapp 分配结果。

local class = require "tinyworld.core.class"

local ServerSpace = class.makeClass("ServerSpace")

function ServerSpace:ctor(config, compiledConfig)
    self.config = compiledConfig or config
    self.id = self.config.id
    self.started = false
end

function ServerSpace:cellAt(x, y)
    return self.config:cellAt(x, y)
end

-- 选择出生 cell: 配置指定 spawnCell 优先, 否则按坐标网格
function ServerSpace:chooseSpawnCell(x, y)
    if self.config.spawnCell then
        return self.config.byCellId[self.config.spawnCell]
    end
    return self.config:cellAt(x, y)
end

function ServerSpace:listCells()
    local out = {}
    for _, info in ipairs(self.config.cells) do
        out[#out + 1] = info:dump()
    end
    return out
end

function ServerSpace:dump()
    return {
        id = self.id,
        width = self.config.width,
        height = self.config.height,
        cellSize = self.config.cellSize,
        aoiRange = self.config.aoiRange,
        ghostRange = self.config.ghostRange,
        balance = self.config.balance,
        cells = self:listCells(),
    }
end

return ServerSpace
