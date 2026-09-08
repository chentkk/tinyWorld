-- server/test/test_timer_wheel.lua
-- 时间轮定时器验收: one-shot / 有限次数 / 无限次数 / removeTimer

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local RealEntity = require "tinyworld.app.cellapp.entities.real_entity"
local SpaceConfig = require "tinyworld.space.space"
local LocalSpace = require "tinyworld.app.cellapp.space.local_space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"

defs.register("TimerDummy", {
    name = "TimerDummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
    },
    records = {},
    containers = {},
})

local config = SpaceConfig.compile({ id = "tw", width = 100, height = 100,
    cellSize = 100, aoiRange = 20, ghostRange = 40 })
CellAllocator.distribute(config, { 1 })

local fake = {
    appId = 1,
    spaceConfig = config,
    now = function(self) return self.time end,
    nextId = function(self) self.seq = (self.seq or 0) + 1 return 7000 + self.seq end,
    call = function() return true end,
    send = function() end,
    sendToClient = function() end,
    notifyEntityMoved = function() end,
}

local space = LocalSpace.new(fake)
for _, info in ipairs(config.cells) do space:addLocalCell(info) end
local cell = space:getCell("0:0")
assert(cell, "cell exists")

local ent = RealEntity.new(defs.get("TimerDummy"), 1, "TimerDummy", space, cell)
cell:addEntity(ent)

-- 1) one-shot: 0.2s 后触发一次
local oneshot = 0
ent:addTimer(0.2, 1, function()
    oneshot = oneshot + 1
end)
for _ = 1, 3 do cell:updateTimers(0.1) end
assert(oneshot == 1, "one-shot should fire once")

-- 2) 有限次数: 0.3s 间隔, 共 3 次
local limited = 0
local lid = ent:addTimer(0.3, 3, function()
    limited = limited + 1
end)
for _ = 1, 10 do cell:updateTimers(0.1) end
print("limited total", limited)
assert(limited == 3, "limited timer should fire 3 times")

-- 3) 无限次数: 0.1s 触发, 10 tick 内应触发多次
local infinite = 0
ent:addTimer(0.1, -1, function()
    infinite = infinite + 1
end)
for _ = 1, 10 do cell:updateTimers(0.1) end
print("infinite total", infinite)
assert(infinite >= 5 and infinite <= 10, "infinite timer should fire continuously after interval")

-- 4) removeTimer: 立即移除未到期的定时器
local removed = 0
local id = ent:addTimer(0.5, 1, function()
    removed = removed + 1
end)
ent:removeTimer(id)
for _ = 1, 10 do cell:updateTimers(0.1) end
assert(removed == 0, "removed timer must not fire")

print("PASS test_timer_wheel")
