-- server/test/test_migrate_rpc.lua
-- 迁移后组件 RPC 必须仍然可用:
--   组件在 onCreate 里注册 client/real rpc; 迁移会重建 RealEntity 实例,
--   因此 promoteGhost 之后必须重新触发组件 onCreate, 否则新实体上
--   没有任何 rpc 注册, 迁移后客户端指令全部静默失败。
--
-- 这个测试复现并锁定该行为。

package.path = "./?.lua;./?/init.lua;" .. package.path

package.preload["test.migrate_rpc_probe"] = function()
    local component = require "tinyworld.entity.component"
    local Probe = component.extend("MigrateRpcProbe")
    Probe.createCount = 0
    function Probe:onCreate()
        Probe.createCount = Probe.createCount + 1
        self:registerRealRpc("probePing")
    end
    function Probe:probePing(data)
        return { pong = (data and data.n) or 0 }
    end
    return Probe
end

local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LocalSpace = require "tinyworld.app.cellapp.space.local_space"
local RealEntity = require "tinyworld.app.cellapp.entities.real_entity"
local defs = require "tinyworld.entity.defs"

defs.register("RpcDummy", {
    name = "RpcDummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
    },
    records = {},
    containers = {},
    cellComponents = { "test.migrate_rpc_probe" },
})

local config = SpaceConfig.compile({ id = "rpcmv", width = 200, height = 100,
    aoiRange = 20, ghostRange = 40, cellSize = 100, minMigrateInterval = 0, hysteresis = 5 })
CellAllocator.distribute(config, { 1 })

local app = { appId = 1, time = 100, seq = 0, spaceConfig = config }
function app:now() return self.time end
function app:sendToClient() end
function app:notifyEntityMoved() end
local space = LocalSpace.new(app)
for _, info in ipairs(config.cells) do space:addLocalCell(info) end

local cellA = space:getCell("0:0")
local cellB = space:getCell("1:0")

local real = RealEntity.new(defs.get("RpcDummy"), 8001, "RpcDummy", space, cellA)
real.props:load({ x = 20, y = 50 })
cellA:addEntity(real)
real:openViews(real.def.cellOpenViews)
real:setupComponents(real.def.cellComponents)
real:onCreate()

local probe = require "test.migrate_rpc_probe"
assert(probe.createCount == 1, "component onCreate runs once on spawn")
local before = real:dispatchRealRpc("probePing", { n = 1 })
assert(before and before.pong == 1, "rpc works before migration")

-- 触发迁移
real:set("x", 150)
cellA:tick(0)

local moved = cellB:get(8001)
assert(moved and moved.isReal, "real migrated to cellB")

-- 迁移后组件 onCreate 必须重新触发, rpc 才能在新实体实例上注册
local after = moved:dispatchRealRpc("probePing", { n = 2 })
assert(after and after.pong == 2,
    "rpc must work after migration (component onCreate must re-run)")

print("PASS migrate-rpc")
