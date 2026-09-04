-- server/test/test_server_object.lua
-- 纯服务器对象验收:
--   1. manager.Create 创建成功
--   2. networked=false: 不进玩家 visibleEntities, 不产生 outbox
--   3. onEnter / onExit 区域进出回调
--   4. duration 到期销毁

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local RealEntity = require "tinyworld.app.cellapp.real_entity"
local SpaceConfig = require "tinyworld.space.space"
local LocalSpace = require "tinyworld.app.cellapp.local_space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"

defs.register("ServerObject", require "game.def.server_object.server_object_def")
defs.register("NetDummy", {
    name = "NetDummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
        { name = "hp", type = "number", sync = "all", default = 100 },
    },
    records = {},
    containers = {},
})

local config = SpaceConfig.compile({ id = "srv", width = 200, height = 200,
    cellSize = 200, aoiRange = 60, ghostRange = 120 })
CellAllocator.distribute(config, { 1 })

local fake = {
    appId = 1,
    time = 100,
    spaceConfig = config,
    now = function(self) return self.time end,
    nextId = function(self) self.seq = (self.seq or 0) + 1 return 9000 + self.seq end,
    call = function(self, ...) return true end,
    send = function(self, ...) end,
    sendToClient = function(self, ...) end,
    notifyEntityMoved = function(self, ...) end,
}

local space = LocalSpace.new(fake)
for _, info in ipairs(config.cells) do space:addLocalCell(info) end
local cell = space:getCell("0:0")
assert(cell, "single cell exists")

-- cell.host.spawn_entity mock: manager 会经由它创建 real
local function spawnEntity(spaceId, cellKey, kind, data, baseApp)
    local real = RealEntity.new(defs.get(kind), 8100 + (data.ownerId or 0), kind, space, cell)
    local x = data.props.x
    local y = data.props.y
    real.x, real.y = x, y
    for k, v in pairs(data.props) do
        if k ~= "x" and k ~= "y" then real:set(k, v) end
    end
    real.ability = data.ability
    rawset(real, "runtime", data.runtime)
    real.baseApp = baseApp
    cell:addEntity(real)
    real:openViews(real.def.cellOpenViews)
    real:setupComponents(real.def.cellComponents)
    real.readyForSync = true
    return { entityId = real.id }
end
cell.host.spawn_entity = spawnEntity

local ServerObject = require "tinyworld.app.cellapp.server_object"

local entered, exited, destroyed
local ok = ServerObject.Create(cell, {
    x = 100, y = 100, radius = 20, duration = 0.2,
    onEnter = function(_, other) entered = other; end,
    onExit = function(_, other) exited = other; end,
    onDestroy = function() destroyed = true end,
})
assert(ok and ok.entityId, "manager.Create should return server object info")

local srv = cell:get(ok.entityId)
assert(srv, "server object in cell")
assert(srv:isNetworked() == false, "ServerObject should be non-networked")

-- 一个网络玩家
local player = RealEntity.new(defs.get("NetDummy"), 1, "NetDummy", space, cell)
player.props:load({ x = 200, y = 200 })
cell:addEntity(player)

-- 完整 tick: ServerObject 不产生 outbox; 玩家(网络对象)会产生 outbox
cell:tick(0)
assert(rawget(srv, "outbox") == nil, "server object must not build outbox")
assert(rawget(player, "outbox") ~= nil, "networked player should build outbox")

-- 视野不应包含 ServerObject
cell:updatePlayerVisibility(player)
assert(player.visibleEntities[srv.id] == nil, "server object must not appear in player visibility")

-- 移动玩家进入半径, tick 触发 onEnter / outbox 行为
player.props:set("x", 102)
player.props:set("y", 100)
cell:syncAoi()

-- 直接驱动 server object 组件 onTick, 触发区域检测
local comp = srv:getComponent("server_object")
assert(comp, "server object component present")
comp:onTick(0.1)
assert(entered == player, "onEnter should fire when player enters radius")

-- 移动玩家离开半径
player.props:set("x", 200)
player.props:set("y", 200)
cell:syncAoi()
comp:onTick(0.1)
assert(exited == player, "onExit should fire when player leaves radius")

-- 再次进半径与 duration 销毁
player.props:set("x", 102)
player.props:set("y", 100)
cell:syncAoi()
comp:onTick(0.1)
comp:onTick(0.1)
assert(destroyed, "duration should destroy server object")
print("PASS test_server_object")
