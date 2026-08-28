-- game/components/sync_stress.lua
-- 数据同步压力测试组件。挂在 cell real 上随机改属性,
-- 挂在 baseentity 上随机操作表格/容器, 用于验证全链路同步。

local component = require "tinyworld.entity.component"

local SyncStress = component.extend("SyncStress")

function SyncStress:ctor(entity, name)
    component.ctor(self, entity, name)
    self.kind = name == "cell_sync_stress" and "cell" or "base"
    self.timer = 0
    self.step = 0
end

function SyncStress:onTick(dt)
    self.timer = self.timer + dt
    if self.timer < 2 then return end
    self.timer = 0
    self.step = self.step + 1

    if self.kind == "cell" then
        self:onTickCell()
    else
        self:onTickBase()
    end
end

function SyncStress:onTickCell()
    local entity = self.entity
    local hp = (entity:get("hp") or 100) % 97 + 1
    local gold = (entity:get("gold") or 0) + 10
    entity:set("hp", hp)
    entity:set("gold", gold)
end

function SyncStress:onTickBase()
    local entity = self.entity

    -- 表格: current_tasks 随机 add / 直接修改 / remove
    local tasks = entity:getRecord("current_tasks")
    local op1 = self.step % 3

    if op1 == 0 then
        tasks:add({ taskid = 900 + self.step, state = 0, progress = 0 })
    else
        local rows = tasks:rowsList()
        if rows[1] then
            local key = tasks.def:keyOf(rows[1]:data())
            if op1 == 1 then
                rows[1].progress = rows[1].progress + 1
            else
                tasks:remove(key)
            end
        end
    end

    -- 容器/视图: bag 随机 add / 直接修改 / remove
    local bag = entity:getContainer("bag")
    local op2 = self.step % 3

    if op2 == 0 then
        local id = 2000 + self.step
        bag:add({ id = id, slot = id, itemId = 7000 + self.step, count = self.step % 5 + 1 })
    else
        local id, child = next(bag.children)
        if child then
            if op2 == 1 then
                child.count = child.count + 1
            else
                bag:remove(id)
            end
        end
    end
end

return SyncStress
