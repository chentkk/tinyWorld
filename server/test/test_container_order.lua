-- server/test/test_container_order.lua
-- 容器子对象顺序必须在 dump/load(迁移/存盘)与 childrenList 之间保持一致:
-- 客户端按 index 访问子对象(如 onCastAbility{index}), 若序列化用 pairs 导致
-- 顺序漂移, 迁移后就会指到错误的子对象。

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LocalSpace = require "tinyworld.app.cellapp.space.local_space"
local RealEntity = require "tinyworld.app.cellapp.entities.real_entity"

defs.register("OrderDummy", {
    name = "OrderDummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
    },
    records = {},
    containers = {
        { name = "inv", persist = true, sync = "all",
          props = {},
          childDef = { name = "item", props = {
              { name = "id", type = "number", sync = "all" },
              { name = "itemId", type = "number", sync = "all" },
          }, records = {} } },
    },
})

local config = SpaceConfig.compile({ id = "ordmv", width = 200, height = 100,
    aoiRange = 20, ghostRange = 40, cellSize = 100, minMigrateInterval = 0, hysteresis = 5 })
CellAllocator.distribute(config, { 1 })
local app = { appId = 1, time = 100, seq = 0, spaceConfig = config }
function app:now() return self.time end
function app:sendToClient() end
function app:notifyEntityMoved() end
local space = LocalSpace.new(app)
for _, c in ipairs(config.cells) do space:addLocalCell(c) end
local cellA = space:getCell("0:0")
local cellB = space:getCell("1:0")

local real = RealEntity.new(defs.get("OrderDummy"), 1, "OrderDummy", space, cellA)
real.props:load({ x = 20, y = 50 })
cellA:addEntity(real)
real:openViews(real.def.cellOpenViews)
real:setupComponents(real.def.cellComponents)
real:onCreate()

-- 以明确的插入顺序添加多个子对象
local inv = real:getContainer("inv")
local ids = { 10, 20, 30, 40, 50, 60, 70, 80 }
for _, id in ipairs(ids) do
    inv:addFromData({ id = id, itemId = id * 100 })
end

local function listIds(cont)
    local out = {}
    for _, c in ipairs(cont:childrenList()) do out[#out + 1] = c:objectId() end
    return out
end
assert(table.concat(listIds(inv), ",") == "10,20,30,40,50,60,70,80", "insertion order")

-- dump 顺序应与 childrenList 一致
local dumped = inv:dump()
local dumpedIds = {}
for _, d in ipairs(dumped) do dumpedIds[#dumpedIds + 1] = d.id end
assert(table.concat(dumpedIds, ",") == "10,20,30,40,50,60,70,80", "dump order must follow insertion")

-- 迁移后顺序保持
real:set("x", 150)
cellA:tick(0)
local moved = cellB:get(1)
assert(moved and moved.isReal, "migrated")
assert(table.concat(listIds(moved:getContainer("inv")), ",") == "10,20,30,40,50,60,70,80",
    "order must survive migration")

print("PASS container-order")
