-- server/test/perf_schema.lua
-- 属性 / 表格 / 容器 性能压测。

package.path = "./?.lua;./?/init.lua;" .. package.path

local entity = require "tinyworld.entity.entity"

local def = entity.compileDef({
    name = "Perf",
    props = { { name = "v", type = "number", sync = "all", persist = true, default = 0 } },
    records = {
        { name = "rec", keyFields = { "id" }, sync = "all", fields = {
            { name = "id", type = "number", sync = "all" },
            { name = "v", type = "number", sync = "all", default = 0 } } },
    },
    containers = {
        { name = "bag", persist = false,
          childProps = { { name = "id", type = "number" }, { name = "v", type = "number", sync = "all" } } },
    },
})

local e = entity.Entity.new(def, 1, "Perf")

local t0 = os.clock()
for i = 1, 200000 do
    e:set("v", i)
end
local propSec = os.clock() - t0

local rec = e:getRecord("rec")
t0 = os.clock()
for i = 1, 100000 do
    rec:add({ id = i, v = i })
end
local addSec = os.clock() - t0

t0 = os.clock()
rec:update("50000", { v = 123456 })
local upSec = os.clock() - t0

local bag = e:getContainer("bag")
bag:openView("x")
t0 = os.clock()
for i = 1, 100000 do
    bag:add({ id = i, v = i })
end
local bagSec = os.clock() - t0

print(("[perf_schema] prop 200k=%.3fs rec-add 100k=%.3fs rec-upd=%.6fs bag-add 100k=%.3fs"):format(propSec, addSec, upSec, bagSec))
