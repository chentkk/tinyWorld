-- tinyworld/entity/component.lua
-- 组件基类。组件挂在 entity 上, 通过字符串方式注册各类 rpc,
-- 可侦听 / 抛出事件, 实现完整生命周期回调。

local class = require "tinyworld.core.class"
local M = {}

local Component = class.makeClass("Component")

function Component:ctor(entity, name)
    self.entity = entity
    self.name = name or self._name
end

function Component:registerClientRpc(methodName, needLogin)
    self.entity:registerClientRpc(self, methodName, needLogin)
end

function Component:registerCellRpc(methodName)
    self.entity:registerCellRpc(self, methodName)
end

function Component:registerBaseRpc(methodName)
    self.entity:registerBaseRpc(self, methodName)
end

function Component:listen(eventName, fn)
    return self.entity:on(eventName, fn)
end

function Component:emit(eventName, ...)
    return self.entity:emit(eventName, ...)
end

-- 生命周期回调由 entity 在对应时机调用, 组件按需覆盖
function Component:onCreate() end
function Component:onDestroy() end
function Component:onEnterCell(cell) end
function Component:onLeaveCell(cell) end
function Component:onClientEnter(playerId) end
function Component:onClientLeave(playerId) end
function Component:onTick(dt) end

M.Component = Component
return M
