-- game/components/bag.lua
-- 背包组件: 使用通用容器 View 实现, 自动同步客户端。

local component = require "tinyworld.entity.component"

local Bag = component.extend("Bag")

function Bag:ctor(entity, name)
    component.ctor(self, entity, name)
end

function Bag:onCreate()
    self:registerClientRpc("onMoveBagItem")
end

-- 客户端 rpc: 交换两个格子(简化演示)
function Bag:onMoveBagItem(d)
    local bag = self.entity:getContainer("bag")
    if not bag or not bag:isViewOpened() then return nil end

    local a = bag:get(d.fromId)
    if not a then return { code = 1, msg = "item not found" } end

    a.slot = tonumber(d.toSlot) or a.slot
    return nil
end

-- 业务接口: 添加道具
function Bag:addItem(itemId, count)
    local bag = self.entity:getContainer("bag")
    if not bag then return nil end

    local slot = 0
    while bag:has(slot) do slot = slot + 1 end
    bag:add({ id = slot, slot = slot, itemId = itemId, count = count or 1 })
    return slot
end

function Bag:removeItem(id)
    local bag = self.entity:getContainer("bag")
    if bag then bag:remove(id) end
end

return Bag
