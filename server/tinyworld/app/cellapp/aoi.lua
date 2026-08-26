-- tinyworld/space/aoi.lua
-- 网格 AOI(先简单实现)。cell 内再按 cellSize/4 划分网格,
-- 查询可视列表时遍历附近网格, 按 aoiRange 精确过滤。

local M = {}

local Aoi = {}
Aoi.__index = Aoi

function Aoi.new(range, cellW, cellH)
    local self = setmetatable({}, Aoi)
    self.range = range or 20
    self.grid = {}
    self.gridSize = math.max(8, math.floor(math.min(cellW, cellH) / 4))
    self.cellW = cellW
    self.cellH = cellH
    return self
end

function Aoi:gridKey(x, y)
    local gx = math.floor(x / self.gridSize)
    local gy = math.floor(y / self.gridSize)
    return gx .. ":" .. gy
end

function Aoi:enter(entity, x, y)
    local key = self:gridKey(x, y)
    local bucket = self.grid[key]
    if not bucket then
        bucket = {}
        self.grid[key] = bucket
    end
    bucket[entity.id] = entity
end

function Aoi:move(entity, oldX, oldY, x, y)
    local oldKey = self:gridKey(oldX, oldY)
    local newKey = self:gridKey(x, y)
    if oldKey ~= newKey then
        local bucket = self.grid[oldKey]
        if bucket then bucket[entity.id] = nil end
        self:enter(entity, x, y)
    end
end

function Aoi:leave(entity, x, y)
    local bucket = self.grid[self:gridKey(x, y)]
    if bucket then bucket[entity.id] = nil end
end

-- 查询周围对象(不含自身)
function Aoi:query(x, y)
    local gx = math.floor(x / self.gridSize)
    local gy = math.floor(y / self.gridSize)
    local radius = math.ceil(self.range / self.gridSize) + 1
    local out = {}
    local range = self.range

    for dx = -radius, radius do
        for dy = -radius, radius do
            local bucket = self.grid[(gx + dx) .. ":" .. (gy + dy)]
            if bucket then
                for id, entity in pairs(bucket) do
                    local ex, ey = entity.x, entity.y
                    local ddx = ex - x
                    local ddy = ey - y
                    if ddx * ddx + ddy * ddy <= range * range then
                        out[#out + 1] = entity
                    end
                end
            end
        end
    end
    return out
end

M.Aoi = Aoi
return M
