-- server/test/perf_aoi.lua
-- 空间索引查询与视野刷新的性能压测(十字链表跳表)。

package.path = "./?.lua;./?/init.lua;" .. package.path

local SpatialIndex = require "tinyworld.app.cellapp.space.spatial_index"

local sp = SpatialIndex.new(50, 100, 100)

for i = 1, 5000 do
    local x, y = math.random(0, 300), math.random(0, 300)
    sp:enter({ id = i, x = x, y = y }, x, y)
end

local t0 = os.clock()
for i = 1, 2000 do
    sp:query(math.random(0, 300), math.random(0, 300))
end
local sec = os.clock() - t0
print(("[perf_spatial_index] 5000 entity, 2000 query = %.3fs"):format(sec))
