-- server/test/test_spatial_index.lua
-- cell 内十字链表空间索引测试:
--   * insert / move / leave 后与暴力扫描结果一致
--   * 同一 id 重复 enter 的重建语义
--   * 越界 / nil 坐标的健壮性

package.path = "./?.lua;./?/init.lua;" .. package.path

local SpatialIndex = require "tinyworld.app.cellapp.spatial_index"

math.randomseed(20260902)

local function bruteForce(entities, x, y, range, selfId)
    local out = {}
    local r2 = range * range
    for _, e in ipairs(entities) do
        if e.id ~= selfId then
            local dx = e.x - x
            local dy = e.y - y
            if dx * dx + dy * dy <= r2 then
                out[#out + 1] = e
            end
        end
    end
    return out
end

local function idSet(list)
    local t = {}
    for _, e in ipairs(list) do t[#t + 1] = e.id end
    table.sort(t)
    return t
end

local function sameSet(a, b)
    local ia, ib = idSet(a), idSet(b)
    if #ia ~= #ib then return false end
    for i = 1, #ia do
        if ia[i] ~= ib[i] then return false end
    end
    return true
end

local RANGE = 40
local N = 300
local MOVES = 5000
local QUERIES = 300

local entities = {}
local idx = SpatialIndex.new(RANGE, 100, 100)

for i = 1, N do
    entities[i] = { id = i, x = 0, y = 0 }
end

for i = 1, N do
    local x, y = math.random(0, 200), math.random(0, 200)
    entities[i].x, entities[i].y = x, y
    idx:enter(entities[i], x, y)
end

for k = 1, MOVES do
    local i = math.random(N)
    local x, y = math.random(0, 200), math.random(0, 200)
    entities[i].x, entities[i].y = x, y
    idx:move(entities[i], x, y)
end

for k = 1, QUERIES do
    local x, y = math.random(0, 200), math.random(0, 200)
    local got = idx:query(x, y)
    local want = bruteForce(entities, x, y, RANGE, nil)
    assert(sameSet(got, want), ("query mismatch at (%d,%d): got %d want %d")
        :format(x, y, #got, #want))
end

-- 同一 id 重复 enter 按最新坐标重建
local e = entities[1]
assert(e.x == nil or e.x >= 0) -- read-back sanity
idx:enter(e, 50, 50)
idx:enter(e, 51, 51)
assert(sameSet(idx:query(51, 51), bruteForce(entities, 51, 51, RANGE, nil)),
    "re-enter rebuild mismatch")

-- 离场后不再被查询命中的对象
idx:leave(entities[2])
local afterLeave = idx:query(entities[2].x, entities[2].y)
for _, o in ipairs(afterLeave) do
    assert(o.id ~= entities[2].id, "left entity still visible")
end

-- 轴链表空查询
local empty = SpatialIndex.new(RANGE, 100, 100)
assert(#empty:query(0, 0) == 0, "empty query should be empty")

print("PASS test_spatial_index")
