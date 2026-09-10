-- server/test/test_direction.lua
-- 朝向: dir 存连续角度(弧度), 支持任意方向自由移动;
-- 客户端按 4 方向美术量化。验证换算与 Move 组件更新 entity.dir。

package.path = "./?.lua;./?/init.lua;" .. package.path

local direction = require "tinyworld.core.direction"

-- 角度归一化 / 差值
assert(math.abs(direction.normalize(0)) < 1e-9, "normalize 0")
assert(math.abs(direction.normalize(3 * math.pi) - math.pi) < 1e-9
    or math.abs(direction.normalize(3 * math.pi) + math.pi) < 1e-9, "normalize wrap")
assert(math.abs(direction.delta(0.1, -0.1) - 0.2) < 1e-9, "delta simple")
assert(math.abs(math.abs(direction.delta(math.pi - 0.1, -math.pi + 0.1)) - 0.2) < 1e-9, "delta wrap short way")

-- 向量 -> 连续角度
assert(math.abs(direction.angleFromVector(1, 0) - 0) < 1e-9, "right angle 0")
assert(math.abs(direction.angleFromVector(0, 1) - math.pi / 2) < 1e-9, "down angle pi/2")
assert(math.abs(math.abs(direction.angleFromVector(-1, 0)) - math.pi) < 1e-9, "left angle pi")
assert(math.abs(direction.angleFromVector(0, -1) + math.pi / 2) < 1e-9, "up angle -pi/2")
-- 对角线方向保持连续(45 度, 不被量化)
local d45 = direction.angleFromVector(1, 1)
assert(math.abs(d45 - math.pi / 4) < 1e-9, "diagonal keeps continuous angle")
assert(direction.angleFromVector(0, 0) == nil, "zero vector -> nil")

-- 量化到 4 方向(仅客户端美术用)
assert(direction.quantize(direction.angleFromVector(1, 0)) == direction.RIGHT, "quantize right")
assert(direction.quantize(direction.angleFromVector(0, 1)) == direction.DOWN, "quantize down")
assert(direction.quantize(direction.angleFromVector(-1, 0)) == direction.LEFT, "quantize left")
assert(direction.quantize(direction.angleFromVector(0, -1)) == direction.UP, "quantize up")
assert(direction.quantize(math.pi / 4) == direction.RIGHT, "quantize 45deg -> right (nearest)")
assert(direction.quantize(3 * math.pi / 4) == direction.DOWN, "quantize 135deg -> down")

-- Move 组件: 移动后 entity.dir = 连续移动角度
local defs = require "tinyworld.entity.defs"
local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LocalSpace = require "tinyworld.app.cellapp.space.local_space"
local RealEntity = require "tinyworld.app.cellapp.entities.real_entity"

defs.register("MoveDummy", {
    name = "MoveDummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
        { name = "dir", type = "number", sync = "all", default = 0 },
        { name = "speed", type = "number", sync = "all", default = 150 },
    },
    records = {},
    containers = {},
    cellComponents = { "game.cell.move" },
})

local config = SpaceConfig.compile({ id = "dirmv", width = 400, height = 400,
    aoiRange = 30, ghostRange = 60, cellSize = 400, minMigrateInterval = 0, hysteresis = 5 })
CellAllocator.distribute(config, { 1 })
local app = { appId = 1, time = 100, seq = 0, spaceConfig = config }
function app:now() return self.time end
function app:sendToClient() end
function app:notifyEntityMoved() end
local space = LocalSpace.new(app)
for _, c in ipairs(config.cells) do space:addLocalCell(c) end
local cell = space:getCell("0:0")

local real = RealEntity.new(defs.get("MoveDummy"), 1, "MoveDummy", space, cell)
real.props:load({ x = 200, y = 200 })
cell:addEntity(real)
real:setupComponents(real.def.cellComponents)
real:onCreate()

local function move(dx, dy, seq)
    real:dispatchClientRpc("onRequestMove", { seq = seq, dt = 0.1, dirX = dx, dirY = dy })
    cell:tick(0.1)
end

move(1, 0, 1)
assert(math.abs(real:get("dir")) < 1e-9, "facing right")
move(0, 1, 2)
assert(math.abs(real:get("dir") - math.pi / 2) < 1e-9, "facing down")
-- 斜向移动: dir 保持连续(45 度), 不量化
move(1, 1, 3)
assert(math.abs(real:get("dir") - math.pi / 4) < 1e-9, "diagonal facing stays continuous")
assert(direction.quantize(real:get("dir")) == direction.RIGHT, "client quantizes to right")

print("PASS direction")
