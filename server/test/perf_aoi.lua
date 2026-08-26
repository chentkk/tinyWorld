-- server/test/perf_aoi.lua
-- AOI 查询与视野刷新的性能压测。

package.path = "./?.lua;./?/init.lua;" .. package.path

local aoiMod = require "tinyworld.app.cellapp.aoi"

local aoi = aoiMod.Aoi.new(50, 100, 100)

for i = 1, 5000 do
    local x, y = math.random(0, 300), math.random(0, 300)
    aoi:enter({ id = i, x = x, y = y }, x, y)
end

local t0 = os.clock()
for i = 1, 2000 do
    aoi:query(math.random(0, 300), math.random(0, 300))
end
local sec = os.clock() - t0
print(("[perf_aoi] 5000 entity, 2000 query = %.3fs"):format(sec))
