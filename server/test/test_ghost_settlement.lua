-- server/test/test_ghost_settlement.lua
-- ghost -> real 结算路由测试(同 cellapp):
-- 对 ghost 调用 dealDamage/dealHeal 时, 效果落在 real 上。

package.path = "./?.lua;./?/init.lua;" .. package.path

local defs = require "tinyworld.entity.defs"
local SpaceConfig = require "tinyworld.space.space"
local CellAllocator = require "tinyworld.app.world.cell_allocator"
local LocalSpace = require "tinyworld.app.cellapp.local_space"
local RealEntity = require "tinyworld.app.cellapp.ghost_entity" -- placeholder
local combatDamage = require "tinyworld.combat.damage"

defs.register("SettleDummy", {
    name = "SettleDummy",
    props = {
        { name = "x", type = "number", sync = "all" },
        { name = "y", type = "number", sync = "all" },
        { name = "hp", type = "number", sync = "all", persist = true, default = 100 },
        { name = "maxHp", type = "number", sync = "all", persist = true, default = 100 },
    },
    records = {},
    containers = {
        (require "game.def.container.modifiers_view_def"),
    },
})

local Real = require "tinyworld.app.cellapp.real_entity"
local config = SpaceConfig.compile({ id = "s", width = 200, height = 100, aoiRange = 40, ghostRange = 48, cellSize = 100 })
CellAllocator.distribute(config, { 1 })

local fake = {
    appId = 1,
    spaceConfig = config,
    now = function() return 1 end,
    nextId = function(self) self.seq = (self.seq or 0) + 1 return 5000 + self.seq end,
    call = function() return true end,
    send = function() end,
    sendToClient = function() end,
    notifyEntityMoved = function() end,
}

local space = LocalSpace.new(fake)
for _, info in ipairs(config.cells) do space:addLocalCell(info) end

local cellA = space:getCell("0:0")
local cellB = space:getCell("1:0")

local real = Real.new(defs.get("SettleDummy"), 10, "SettleDummy", space, cellA)
real.props:load({ hp = 100 })
cellA:addEntity(real)
real:getContainer("modifiers_view"):openView("modifiers")
real:addComponent("combat_agent", require "tinyworld.combat.combat_agent")

local ghost = cellB:buildGhost(real)
ghost.realApp = fake.appId
ghost.realCellKey = cellA:key()
cellB:addEntity(ghost)

local hpBefore = real:get("hp")
local dealt = combatDamage.dealDamage(real, ghost, 30, combatDamage.DAMAGE_TYPE.MAGICAL, nil)
assert(dealt == 30)
assert(real:get("hp") == hpBefore - 30, ("ghost damage should hit real hp: %d"):format(real:get("hp")))

combatDamage.dealHeal(real, ghost, 10, combatDamage.HEAL_TYPE.HEAL, nil)
assert(real:get("hp") == hpBefore - 20, "ghost heal should hit real hp")

print("PASS test_ghost_settlement")
