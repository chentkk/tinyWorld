-- server/test/test_batch_sync.lua
-- 每 tick 发给同一玩家的所有 around 变更必须合并成一份 batch,
-- 而不是每个实体/每种消息各发一次(减少跨服务发送与编码)。

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LocalSpace = require "tinyworld.app.cellapp.space.local_space"
local RealEntity = require "tinyworld.app.cellapp.entities.real_entity"

defs.register("BatchDummy", {
    name = "BatchDummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
        { name = "hp", type = "number", sync = "all", default = 100 },
    },
    records = {},
    containers = {},
})

local config = SpaceConfig.compile({ id = "batch", width = 400, height = 400,
    aoiRange = 100, ghostRange = 200, cellSize = 400, minMigrateInterval = 0, hysteresis = 5 })
CellAllocator.distribute(config, { 1 })

local sent = {}
local app = { appId = 1, time = 100, seq = 0, spaceConfig = config }
function app:now() return self.time end
function app:notifyEntityMoved() end
function app:sendToClient(player, msg) sent[#sent + 1] = { playerId = player.id, msg = msg } end

local space = LocalSpace.new(app)
for _, c in ipairs(config.cells) do space:addLocalCell(c) end
local cell = space:getCell("0:0")

local observer = RealEntity.new(defs.get("BatchDummy"), 1, "BatchDummy", space, cell)
observer.props:load({ x = 100, y = 100 })
cell:addEntity(observer)

local others = {}
for i = 2, 4 do
    local e = RealEntity.new(defs.get("BatchDummy"), i, "BatchDummy", space, cell)
    e.props:load({ x = 110, y = 100 + i })
    cell:addEntity(e)
    others[#others + 1] = e
end

-- 先建立视野(object add 各一次), 之后清空记录
cell:updatePlayerVisibility(observer)
assert(#sent >= 3, "observer should see 3 others")

-- 三个 other 本 tick 都有属性变更
for _, e in ipairs(others) do e:set("hp", e:get("hp") - 1) end
cell:buildOutboxes()

sent = {}
cell:deliverToPlayer(observer)
assert(#sent == 1, "expected ONE batched send this tick, got " .. tostring(#sent))
local msg = sent[1].msg
assert(msg.t == "batch" and msg.n == "msgs", "expected batch envelope")
assert(#msg.d.msgs >= 3, "batch should carry all 3 others' updates")
local ids = {}
for _, sub in ipairs(msg.d.msgs) do
    assert(sub.t == "prop", "sub message type " .. tostring(sub.t))
    ids[sub.d.entityId] = true
end
assert(ids[2] and ids[3] and ids[4], "all 3 others must be present in one batch")

-- 没有任何变更时不发送
cell:buildOutboxes()
sent = {}
cell:deliverToPlayer(observer)
assert(#sent == 0, "no changes -> no send")

print("PASS batch-sync")
