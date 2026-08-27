-- tinyworld/space/space.lua
-- Space 通用定义: 空间尺寸、cell 网格划分、邻居关系与 cell 归属。
-- world 侧使用 ServerSpace 保存完整信息, cellapp 侧使用 LocalSpace 管理本地 cell。

local CellInfo = require "tinyworld.space.cell_info"
local util = require "tinyworld.core.util"

local SpaceConfig = {}
SpaceConfig.__index = SpaceConfig

-- config: { id, width, height, cellSize, aoiRange, balance, cellApps }
function SpaceConfig.compile(config, defaultAppIds)
    local self = setmetatable({}, SpaceConfig)
    self.id = config.id or "main"
    self.width = config.width or 200
    self.height = config.height or 200
    self.cellSize = config.cellSize or 40
    self.aoiRange = config.aoiRange or 60
    self.balance = config.balance or { enabled = false, strategy = 2 }
    self.hysteresis = config.hysteresis or math.max(2, self.cellSize * 0.08)
    self.minMigrateInterval = config.minMigrateInterval or 1.0
    self.ghostRange = config.ghostRange or math.min(self.cellSize, self.aoiRange)
    self.appIds = config.cellApps or defaultAppIds or { 1 }

    self.cols = math.max(1, math.ceil(self.width / self.cellSize))
    self.rows = math.max(1, math.ceil(self.height / self.cellSize))

    self.cells = {}
    self.byCoord = {}
    local assigned = {}

    local function ref(i)
        if assigned[i] then return assigned[i] end
        assigned[i] = self.appIds[((i - 1) % #self.appIds) + 1]
        return assigned[i]
    end

    for cy = 0, self.rows - 1 do
        for cx = 0, self.cols - 1 do
            local x = cx * self.cellSize
            local y = cy * self.cellSize
            local w = math.min(self.cellSize, self.width - x)
            local h = math.min(self.cellSize, self.height - y)
            local idx = self.cols * cy + cx + 1
            local appId
            if config.cells then
                appId = config.cells[cx .. ":" .. cy] or ref(idx)
            else
                appId = ref(idx)
            end
            local info = CellInfo.new(cx, cy, x, y, w, h, appId)
            self.cells[#self.cells + 1] = info
            self.byCoord[info.id] = info
        end
    end

    self.bounds = { x1 = 0, y1 = 0, x2 = self.width, y2 = self.height }
    for _, info in ipairs(self.cells) do
        info:setGhostRange(self.ghostRange, self.bounds)
    end
    return self
end

function SpaceConfig:cellAt(x, y)
    if x < 0 or y < 0 or x >= self.width or y >= self.height then
        return self.byCoord[(self.cols - 1) .. ":" .. (self.rows - 1)]
    end
    local cx = math.floor(x / self.cellSize)
    local cy = math.floor(y / self.cellSize)
    cx = math.min(cx, self.cols - 1)
    cy = math.min(cy, self.rows - 1)
    return self.byCoord[cx .. ":" .. cy]
end

function SpaceConfig:neighbors(cellInfo)
    local out = {}
    for dy = -1, 1 do
        for dx = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local key = (cellInfo.cx + dx) .. ":" .. (cellInfo.cy + dy)
                local n = self.byCoord[key]
                if n then out[#out + 1] = n end
            end
        end
    end
    return out
end

-- 矩形到点最近距离平方(0 表示在内部)
function SpaceConfig.rectDist2(info, x, y)
    local dx = 0
    local dy = 0
    if x < info.x then dx = info.x - x
    elseif x >= info.x + info.w then dx = x - (info.x + info.w) end
    if y < info.y then dy = info.y - y
    elseif y >= info.y + info.h then dy = y - (info.y + info.h) end
    return dx * dx + dy * dy
end

return SpaceConfig
