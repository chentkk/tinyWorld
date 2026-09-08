-- tinyworld/core/event.lua
-- 事件总线: 组件系统可侦听 / 抛出事件。
-- on / off / emit, 侦听器签名 listener(eventName, ...)

local class = require "tinyworld.core.class"

local EventBus = class.makeClass("EventBus")

function EventBus:ctor()
    self.listeners = {}
end

function EventBus:on(name, fn)
    local list = self.listeners[name]
    if not list then
        list = {}
        self.listeners[name] = list
    end
    list[#list + 1] = fn
    return fn
end

function EventBus:off(name, fn)
    local list = self.listeners[name]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then
            table.remove(list, i)
        end
    end
end

function EventBus:emit(name, ...)
    local list = self.listeners[name]
    if not list then return end
    -- 拷贝一份, 避免回调中增删监听器导致遍历错乱
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end
    for i = 1, #snapshot do
        snapshot[i](name, ...)
    end
end

return EventBus
