-- server/test/test_custom_data.lua
-- 自定义 Lua 字段迁移规则(不再维护黑名单):
--   * 跳过 props / records / containers(单独序列化);
--   * 跳过 "__" 前缀字段(内部/瞬态约定);
--   * 其余字段只要值是纯数据(标量 / 不含对象实例的 table)就自动收集;
--   * 含对象实例 / function 等不可序列化值的字段视为框架数据, 跳过。

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local Object = require "tinyworld.schema.object"
local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LocalSpace = require "tinyworld.app.cellapp.space.local_space"
local RealEntity = require "tinyworld.app.cellapp.entities.real_entity"

defs.register("CustomDummy", {
    name = "CustomDummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
        { name = "hp", type = "number", sync = "all", default = 100 },
    },
    records = {},
    containers = {},
})

local config = SpaceConfig.compile({ id = "cdmv", width = 200, height = 100,
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

local real = RealEntity.new(defs.get("CustomDummy"), 1, "CustomDummy", space, cellA)
real.props:load({ x = 20, y = 50 })
cellA:addEntity(real)

-- 普通字段: 纯数据自动收集
real.counter = 42
real.flag = true
real.label = "hello"
real.nested = { a = 1, b = { c = 2, list = { 1, 2, 3 } } }
-- "__" 前缀: 不收集
real.__secret = "no migrate"
-- 含对象实例的 table: 不收集(视为框架数据)
real.objHolder = { obj = Object.new(nil, nil) }
-- function: 不收集
real.callback = function() end

local custom = real:collectCustomData()
assert(custom.counter == 42, "scalar collected")
assert(custom.flag == true, "boolean collected")
assert(custom.label == "hello", "string collected")
assert(custom.nested.b.c == 2 and custom.nested.b.list[3] == 3, "nested pure table collected")
assert(custom.__secret == nil, "__ prefix must not be collected")
assert(custom.objHolder == nil, "table containing object must not be collected")
assert(custom.callback == nil, "function must not be collected")

-- 迁移后普通字段完整还原
real.counter = 100
real:set("x", 150)  -- 越过 0:0 右边界
cellA:tick(0)
local moved = cellB:get(1)
assert(moved and moved.isReal, "migrated")
assert(moved.counter == 100, "custom scalar survives migration")
assert(moved.nested.b.c == 2, "custom table survives migration")
assert(moved.__secret == nil, "__ prefix does not migrate")

print("PASS custom-data")
