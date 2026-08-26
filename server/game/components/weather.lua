-- game/components/weather.lua
-- 全局场景天气系统示例(cellapp 侧)。
-- 组件能侦听 / 抛出事件: 天气变化通过实体事件总线广播, 业务自行订阅。

local event = require "tinyworld.core.event"
local M = {}

M.WEATHERS = { "sunny", "rain", "fog", "storm" }

local WeatherSystem = {}
WeatherSystem.__index = WeatherSystem

function WeatherSystem.new()
    local self = setmetatable({ index = 1, timer = 0, event = event.EventBus.new() }, WeatherSystem)
    return self
end

function WeatherSystem:current()
    return M.WEATHERS[self.index]
end

function WeatherSystem:tick(dt)
    self.timer = self.timer + dt
    if self.timer < 10 then return end

    self.timer = 0
    self.index = self.index % #M.WEATHERS + 1
    self.event:emit("weather_change", self:current())
end

M.WeatherSystem = WeatherSystem
return M
