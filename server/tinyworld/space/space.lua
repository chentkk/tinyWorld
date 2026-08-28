-- tinyworld/space/space.lua
-- Space 通用定义: 空间几何、cell 切分、邻居关系与 cell 归属分配。
-- 支持两种切分模式:
--   * auto  : 按 cellSize(或 cellCols/cellRows) 等分整张地图
--   * manual: 配置中直接给出每个 cell 的矩形 {id, x, y, w, h}
-- cell 的 appId 不在配置中指定, 由 world 侧运行时分配(cell_allocator)。
-- 本模块只负责几何切分, 不关心 cellapp。

local CellInfo = require "tinyworld.space.cell_info"

local SpaceConfig = {}
SpaceConfig.__index = SpaceConfig

local function clampInt(n, default)
    n = tonumber(n)
    if not n or n <= 0 then return default end
    return math.floor(n)
end

-- 两个轴对齐矩形是否接触或相交
local function rectsTouch(a, b)
    local ax2 = a.x + a.w
    local ay2 = a.y + a.h
    local bx2 = b.x + b.w
    local by2 = b.y + b.h
    return a.x <= bx2 and ax2 >= b.x and a.y <= by2 and ay2 >= b.y
end

-- config: { id, width, height, aoiRange, ghostRange,
--           cellSize | cellCols+cellRows | cells = { {id,x,y,w,h}, ... } }
function SpaceConfig.compile(config)
    local self = setmetatable({}, SpaceConfig)

    self.id = config.id or "main"
    self.width = tonumber(config.width) or 200
    self.height = tonumber(config.height) or 200
    self.aoiRange = tonumber(config.aoiRange) or 60

    self.balance = config.balance or { enabled = false, strategy = 2 }
    self.minMigrateInterval = tonumber(config.minMigrateInterval) or 1.0

    self.cells = {}
    self.byCellId = {} -- cellId -> CellInfo

    if config.cells and #config.cells > 0 then
        -- 手动切分: 配置定义每个 cell 的矩形
        self.mode = "manual"
        self.cellSize = config.cellSize
        for i, cellDef in ipairs(config.cells) do
            assert(cellDef.id, "manual cell missing id")
            assert(tonumber(cellDef.x) ~= nil, "manual cell missing x: " .. tostring(cellDef.id))
            assert(tonumber(cellDef.y) ~= nil, "manual cell missing y: " .. tostring(cellDef.id))
            assert(tonumber(cellDef.w) and tonumber(cellDef.w) > 0, "manual cell bad w: " .. tostring(cellDef.id))
            assert(tonumber(cellDef.h) and tonumber(cellDef.h) > 0, "manual cell bad h: " .. tostring(cellDef.id))

            local info = CellInfo.new(nil, nil, tonumber(cellDef.x), tonumber(cellDef.y),
                tonumber(cellDef.w), tonumber(cellDef.h), nil, cellDef.id)
            info.id = cellDef.id
            self.cells[#self.cells + 1] = info
            self.byCellId[info.id] = info
        end
    else
        -- 自动切分: cellSize 与 cellCols/cellRows 二选一, 都不给则整图一个 cell
        self.mode = "auto"
        local cols, rows
        if config.cellCols or config.cellRows then
            cols = clampInt(config.cellCols, 1)
            rows = clampInt(config.cellRows, 1)
            self.cellCols = cols
            self.cellRows = rows
            self.cellSize = nil
        else
            local cellSize = tonumber(config.cellSize)
            cellSize = (cellSize and cellSize > 0) and cellSize or math.max(self.width, self.height)
            self.cellSize = cellSize
            cols = math.max(1, math.ceil(self.width / cellSize))
            rows = math.max(1, math.ceil(self.height / cellSize))
        end

        self.cols = cols
        self.rows = rows
        for cy = 0, rows - 1 do
            for cx = 0, cols - 1 do
                local x = cx * (self.width / cols)
                local y = cy * (self.height / rows)
                local w = (cx == cols - 1) and (self.width - x) or (self.width / cols)
                local h = (cy == rows - 1) and (self.height - y) or (self.height / rows)
                local info = CellInfo.new(cx, cy, x, y, w, h, nil)
                self.cells[#self.cells + 1] = info
                self.byCellId[info.id] = info
            end
        end
    end

    -- cellSize 可能是自动模式, 也可能是手动模式未填写; 统一回退为配置值
    self.cellSize = config.cellSize

    self.ghostRange = tonumber(config.ghostRange)
        or tonumber(self.cellSize) or math.min(self.width, self.height)
    self.hysteresis = tonumber(config.hysteresis) or 2

    self.bounds = { x1 = 0, y1 = 0, x2 = self.width, y2 = self.height }
    for _, info in ipairs(self.cells) do
        info:setGhostRange(self.ghostRange, self.bounds)
    end

    return self
end

-- 坐标落点: 自动模式按网格, 手动模式按矩形包含
function SpaceConfig:cellAt(x, y)
    if self.mode == "manual" then
        for _, info in ipairs(self.cells) do
            if x >= info.x and x < info.x + info.w and y >= info.y and y < info.y + info.h then
                return info
            end
        end
        -- 地图外: 退回第一个 cell, 由迁移逻辑做边界抑制
        return self.cells[1]
    end

    x = math.min(math.max(x, 0), self.width - 1)
    y = math.min(math.max(y, 0), self.height - 1)
    local cx = math.floor(x / (self.width / self.cols))
    local cy = math.floor(y / (self.height / self.rows))
    cx = math.min(cx, self.cols - 1)
    cy = math.min(cy, self.rows - 1)
    return self.byCellId[cx .. ":" .. cy]
end

-- 邻居: 自动模式走网格邻居, 手动模式返回所有其他 cell
function SpaceConfig:neighbors(cellInfo)
    local out = {}
    if self.mode == "manual" then
        for _, other in ipairs(self.cells) do
            if other.id ~= cellInfo.id and rectsTouch(other.ghostRect, cellInfo.ghostRect) then
                out[#out + 1] = other
            end
        end
        return out
    end

    for dy = -1, 1 do
        for dx = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local key = (cellInfo.cx + dx) .. ":" .. (cellInfo.cy + dy)
                local n = self.byCellId[key]
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
