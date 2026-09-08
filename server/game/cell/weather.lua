-- game/cell/weather.lua
-- cellapp 侧全局场景天气系统示例。
-- 组件能侦听 / 抛出事件: 天气变化通过实体事件总线广播, 业务自行订阅。

local class = require "tinyworld.core.class"
local event = require "tinyworld.core.event"
local WEATHERS = { "sunny", "rain", "fog", "storm" }

local WeatherSystem = class.makeClass("WeatherSystem")

function WeatherSystem:ctor()
    self.index = 1
    self.timer = 0
    self.event = event.new()
end

function WeatherSystem:current()
    return WEATHERS[self.index]
end

function WeatherSystem:tick(dt)
    self.timer = self.timer + dt
    if self.timer < 10 then return end

    self.timer = 0
    self.index = self.index % #WEATHERS + 1
    self.event:emit("weather_change", self:current())
end

WeatherSystem.WEATHERS = WEATHERS
return WeatherSystem
