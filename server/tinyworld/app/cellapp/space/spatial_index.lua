-- tinyworld/app/cellapp/spatial_index.lua
-- cell 内空间划分索引(十字链表):
--   cell 内所有对象分别挂在 X / Y 两条有序链表上,
--   每条链表由跳表支撑(luaclib/skiplist.so 的 C 实现, 参考 Redis zskiplist)。
--   两条链表组支持 O(log n) 的 enter / move / leave 维护,
--   以及 O(k log n + out) 的 X/Y 区间相交查询。
-- 查询语义: 返回与 (x, y) 欧氏距离 <= range 的所有对象(包含自身, 由调用方过滤)。
--
-- 唯一性约定: C skiplist 与 Redis 一样不额外去重(允许同 (score,id) 重复节点),
-- 因此"同一个 id 只保留最新坐标"由本层保证:
--   - enter: 已存在则先 leave 再 insert;
--   - move:  坐标变化时先 remove 旧坐标再 insert 新坐标;
--   - leave: 先用 self.nodes 中的旧坐标 remove, 再清空索引。
-- 任何情况下不允许跳过 remove 直接 insert。

-- 跳表由 C 模块提供(luaclib/skiplist.so)。
local class = require "tinyworld.core.class"
local Skiplist = require "skiplist"

local SpatialIndex = class.makeClass("SpatialIndex")

function SpatialIndex:ctor(range, cellW, cellH)
    self.range = range or 20
    self.indexX = Skiplist.new()
    self.indexY = Skiplist.new()
    self.nodes = {}  -- id -> { x = number, y = number, ent = entity }
end

function SpatialIndex:enter(entity, x, y)
    x = x or entity.x or 0
    y = y or entity.y or 0

    -- 同 id 重复进入时按最新坐标重建: 先删旧节点再插新节点(C skiplist 不做去重)
    if self.nodes[entity.id] then
        self:leave(entity)
    end
    assert(not self.nodes[entity.id], "spatial_index: stale node after leave")

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
        assert(self.indexX:remove(node.x, entity.id),
            "spatial_index: X node missing during move id=" .. tostring(entity.id))
        self.indexX:insert(x, entity.id)
        node.x = x
    end
    if node.y ~= y then
        assert(self.indexY:remove(node.y, entity.id),
            "spatial_index: Y node missing during move id=" .. tostring(entity.id))
        self.indexY:insert(y, entity.id)
        node.y = y
    end
end

function SpatialIndex:leave(entity)
    local node = self.nodes[entity.id]
    if not node then return end

    assert(self.indexX:remove(node.x, entity.id),
        "spatial_index: X node missing during leave id=" .. tostring(entity.id))
    assert(self.indexY:remove(node.y, entity.id),
        "spatial_index: Y node missing during leave id=" .. tostring(entity.id))
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
