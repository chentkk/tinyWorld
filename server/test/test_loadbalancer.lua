-- server/test/test_loadbalancer.lua
-- 负载平滑与均衡策略的单元测试。

package.path = "./?.lua;./?/init.lua;" .. package.path

local spaceLib = require "tinyworld.space.space"
local lbMod = require "tinyworld.app.world.load_balancer"

local config = spaceLib.SpaceConfig.compile({ id = "lb", width = 100, height = 100,
    cellSize = 50, aoiRange = 10, balance = { enabled = true, strategy = 2 } }, { 1 })

assert(config.balance.enabled == true and config.balance.strategy == 2)

local lb = lbMod.LoadBalancer.new(config)
-- cpu 平滑: 上次 10%, 本次 90%, 不应直接判 90%
local a = lb:report(1, 10, 0.10)
local b = lb:report(1, 10, 0.90)
assert(math.abs(a - 0.10) < 0.001)
assert(b > 0.2 and b < 0.4, "smoothed cpu should be between 0.2 and 0.4, got " .. b)

assert(lb:isEnabled())
assert(type(lb:computeBoundaryAdvice()) == "number")

-- 策略 4 防抖: 高负载迁移到低负载后, 冷却期内不再迁移
local lb4 = lbMod.LoadBalancer.new(spaceLib.SpaceConfig.compile(
    { id = "lb4", width = 100, height = 100, cellSize = 50, aoiRange = 10,
      balance = { enabled = true, strategy = 4 } }, { 1 }))
lb4:report(1, 10, 0.9, { { key = "0:0" } })
lb4:report(2, 10, 0.1, { { key = "1:0" } })
local first = lb4:tryMigrateCell()
assert(first and first.from == 1 and first.to == 2)
assert(lb4:tryMigrateCell() == nil, "anti-jitter migration should cooldown")

print("PASS test_loadbalancer")
