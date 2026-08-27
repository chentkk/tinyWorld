-- game/components/equipment.lua
-- 装备栏组件: 从背包穿装备、脱下装备到背包, 均通过通用容器 View 同步。

local component = require "tinyworld.entity.component"

local Equipment = component.extend("Equipment")

function Equipment:onCreate()
    self:registerClientRpc("onEquipItem")
    self:registerClientRpc("onUnequipItem")
end

-- 穿上: 背包删除 -> 装备栏添加(格子按装备位)
function Equipment:onEquipItem(d)
    local entity = self.entity
    local bag = entity:getContainer("bag")
    local equipment = entity:getContainer("equipment")

    local item = bag:get(d.bagId)
    if not item then return { code = 1, msg = "no item" } end

    local slotName = tonumber(d.slotName) or item.props.slot
    if equipment:has(slotName) then return { code = 2, msg = "slot used" } end

    bag:remove(item.id)
    equipment:add({ id = slotName, slotName = slotName, itemId = item.props.itemId })
    return nil
end

-- 脱下: 装备栏删除 -> 背包添加(放回原格子)
function Equipment:onUnequipItem(d)
    local entity = self.entity
    local bag = entity:getContainer("bag")
    local equipment = entity:getContainer("equipment")

    local item = equipment:get(d.slotName)
    if not item then return { code = 1, msg = "no equip" } end

    equipment:remove(item.id)
    bag:add({ id = item.id, slot = item.id, itemId = item.props.itemId, count = 1 })
    return nil
end

return Equipment
