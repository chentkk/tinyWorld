-- tinyworld/space/cell_info.lua
-- cell 描述信息: 实际管理矩形 + ghost_rect(管理矩形向外扩展 ghost_range)。

local class = require "tinyworld.core.class"

local CellInfo = class.makeClass("CellInfo")

function CellInfo:ctor(cx, cy, x, y, w, h, appId, id)
    self.cx = cx
    self.cy = cy
    self.x = x
    self.y = y
    self.w = w
    self.h = h
    self.appId = appId
    self.id = id or (cx ~= nil and cy ~= nil and (cx .. ":" .. cy)) or nil
    self.ghostRange = 0
    self.ghostRect = { x = x, y = y, w = w, h = h }
end

-- 由 SpaceConfig 编译完成后回填 ghost_rect
function CellInfo:setGhostRange(ghostRange, bounds)
    self.ghostRange = ghostRange or 0
    if bounds then
        self.ghostRect = {
            x = math.max(bounds.x1, self.x - self.ghostRange),
            y = math.max(bounds.y1, self.y - self.ghostRange),
            w = math.min(bounds.x2, self.x + self.w + self.ghostRange) -
                math.max(bounds.x1, self.x - self.ghostRange),
            h = math.min(bounds.y2, self.y + self.h + self.ghostRange) -
                math.max(bounds.y1, self.y - self.ghostRange),
        }
    else
        self.ghostRect = {
            x = self.x - self.ghostRange,
            y = self.y - self.ghostRange,
            w = self.w + self.ghostRange * 2,
            h = self.h + self.ghostRange * 2,
        }
    end
end

-- 位置是否进入本 cell 的 ghost 管理范围(=本 cell 需要这个位置的 ghost)
function CellInfo:ghostContains(x, y)
    local r = self.ghostRect
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function CellInfo:dump()
    return { id = self.id, cx = self.cx, cy = self.cy, x = self.x, y = self.y,
             w = self.w, h = self.h, appId = self.appId,
             ghostRange = self.ghostRange,
             ghostRect = self.ghostRect }
end

return CellInfo
