-- game/cell/sync_stress.lua
-- cellapp 侧数据同步压测组件: 随机改属性, 验证 real->ghost->client 同步链路。
-- 挂在 cell real 上, 由 cellComponents 配置名为 "cell_sync_stress"。

local component = require "tinyworld.entity.component"

local CellSyncStress = component.extend("CellSyncStress")

function CellSyncStress:ctor(entity, name)
    component.ctor(self, entity, name)
    self.timer = 0
    self.step = 0
end

function CellSyncStress:onTick(dt)
    self.timer = self.timer + dt
    if self.timer < 2 then return end
    self.timer = 0
    self.step = self.step + 1

    local entity = self.entity
    local hp = (entity:get("hp") or 100) % 97 + 1
    local gold = (entity:get("gold") or 0) + 10
    entity:set("hp", hp)
    entity:set("gold", gold)
end

return CellSyncStress
