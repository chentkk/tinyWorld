-- tinyworld/app/cellapp/spatial_index.lua
-- cell 内空间划分索引(十字链表):
--   cell 内所有对象分别挂在 X / Y 两条有序链表上,
--   每条链表由跳表支撑, 优先加载 luaclib/skiplist.so 的 C 实现, 失败时退回 lualib/skiplist.lua。
--   两条链表组支持 O(log n) 的 enter / move / leave 维护,
--   以及 O(k log n + out) 的 X/Y 区间相交查询。
-- 查询语义: 返回与 (x, y) 欧氏距离 <= range 的所有对象(包含自身, 由调用方过滤)。

-- C 实现: luaclib/skiplist.so(源码 lualib-src/skiplist.c); Lua 实现: lualib/skiplist.lua
local Skiplist = pcall(require, "skiplist") and require "skiplist"
if not Skiplist then
    Skiplist = require "lualib.skiplist"
end

local SpatialIndex = {}
SpatialIndex.__index = SpatialIndex

function SpatialIndex.new(range, cellW, cellH)
    return setmetatable({
        range = range or 20,
        indexX = Skiplist.new(),
        indexY = Skiplist.new(),
        nodes = {},  -- id -> { x = number, y = number, ent = entity }
    }, SpatialIndex)
end

function SpatialIndex:enter(entity, x, y)
    x = x or entity.x or 0
    y = y or entity.y or 0

    -- 同 id 重复进入时按最新坐标重建, 保证两个轴链表状态一致
    if self.nodes[entity.id] then
        self:leave(entity)
    end

    self.nodes[entity.id] = { x = x, y = y, ent = entity }
    self.indexX:insert(x, entity.id)
    self.indexY:insert(y, entity.id)
end

function SpatialIndex:move(entity, x, y)
    x = x or entity.x or 0
    y = y or entity.y or 0

    local node = self.nodes[entity.id]
    if not node then
        self:enter(entity, x, y)
        return
    end

    if node.x ~= x then
        self.indexX:remove(node.x, entity.id)
        self.indexX:insert(x, entity.id)
        node.x = x
    end
    if node.y ~= y then
        self.indexY:remove(node.y, entity.id)
        self.indexY:insert(y, entity.id)
        node.y = y
    end
end

function SpatialIndex:leave(entity)
    local node = self.nodes[entity.id]
    if not node then return end

    self.indexX:remove(node.x, entity.id)
    self.indexY:remove(node.y, entity.id)
    self.nodes[entity.id] = nil
end

-- 区间相交查询:
-- 先遍历跨度较小的那条轴, 建立候选 id 集合;
-- 再遍历另一条轴区间, 只在两轴区间都覆盖的候选中做精确距离过滤。
-- radius 可选, 默认使用构造时的 range; 调用方(如 projectile)可用更小的 hitRadius 裁剪。
function SpatialIndex:query(x, y, radius)
    assert(x ~= nil and y ~= nil, "spatial_index:query requires x,y")

    local r = radius or self.range
    local r2 = r * r
    local x1, x2 = x - r, x + r
    local y1, y2 = y - r, y + r

    local ids = {}
    local n
    local useXFirst = (x2 - x1) <= (y2 - y1)
    local lo1, hi1, lo2, hi2
    if useXFirst then
        ids = self.indexX:range(x1, x2)
        lo2, hi2 = y1, y2
    else
        ids = self.indexY:range(y1, y2)
        lo2, hi2 = x1, x2
    end

    local cand = {}
    for i = 1, (#ids) do
        cand[ids[i]] = true
    end

    local out = {}
    local ids2
    if useXFirst then
        ids2 = self.indexY:range(y1, y2)
    else
        ids2 = self.indexX:range(x1, x2)
    end

    for i = 1, (#ids2) do
        local id = ids2[i]
        if cand[id] then
            local node = self.nodes[id]
            local dx = node.x - x
            local dy = node.y - y
            if dx * dx + dy * dy <= r2 then
                out[#out + 1] = node.ent
            end
        end
    end

    return out
end

return SpatialIndex
