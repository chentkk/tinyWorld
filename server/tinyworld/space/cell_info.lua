-- tinyworld/space/cell_info.lua
-- cell 描述信息。空间按网格划分为 cell, 每个 cell 分配给某个 cellapp。

local class = require "tinyworld.core.class"

local CellInfo = class.makeClass("CellInfo")

function CellInfo:ctor(cx, cy, x, y, w, h, appId)
    self.cx = cx
    self.cy = cy
    self.x = x
    self.y = y
    self.w = w
    self.h = h
    self.appId = appId
    self.id = cx .. ":" .. cy
end

function CellInfo:contains(x, y)
    return x >= self.x and x < self.x + self.w and y >= self.y and y < self.y + self.h
end

function CellInfo:clip(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function CellInfo:dump()
    return { id = self.id, cx = self.cx, cy = self.cy, x = self.x, y = self.y,
             w = self.w, h = self.h, appId = self.appId }
end

return CellInfo
