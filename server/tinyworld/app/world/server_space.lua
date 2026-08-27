-- tinyworld/space/server_space.lua
-- world 服务侧的完整 space 信息(相当于 bigworld 的 cell 管理器视图)。

local class = require "tinyworld.core.class"
local SpaceConfig = require "tinyworld.space.space"

local ServerSpace = class.makeClass("ServerSpace")

function ServerSpace:ctor(config, appIds)
    self.config = SpaceConfig.compile(config, appIds)
    self.id = config.id
    self.cellapps = config.cellapps or {}
    self.started = false
end

function ServerSpace:cellAt(x, y)
    return self.config:cellAt(x, y)
end

-- 选择出生 cell: 配置文件分配优先, 否则按坐标网格
function ServerSpace:chooseSpawnCell(x, y)
    if self.config.spawnCell then
        return self.config.byCoord[self.config.spawnCell]
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
        balance = self.config.balance,
        cells = self:listCells(),
    }
end

return ServerSpace
