-- tinyworld/combat/modifier.lua
-- Modifier 基类(dota2 风格生命周期)。
-- modifier 的 create/refresh/destroy 会通过实体事件通知上层,
-- 由上层同步系统(如 buff 视图)统一推给客户端, 战斗框架不直接处理网络。

local class = require "tinyworld.core.class"

local Modifier = class.makeClass("Modifier")

function Modifier:ctor(caster, ability, duration)
    self.caster = caster
    self.ability = ability
    self.duration = duration
    self.elapsed = 0
    self.destroyed = false
    self.stack = 1
    self.intervalThink = tonumber(ability and ability.data and ability.data.intervalThink) or 0
end

-- 以下生命周期回调由具体逻辑脚本覆盖
function Modifier:OnCreated(params) end
function Modifier:OnRefresh(params) end
function Modifier:OnDestroy() end
function Modifier:OnIntervalThink() end

function Modifier:GetModifierName()
    return self._name or "modifier"
end

function Modifier:IsPurgable()
    return true
end

function Modifier:update(dt)
    if self.destroyed then return end

    self.elapsed = self.elapsed + dt
    if self.intervalThink > 0 and self.elapsed % self.intervalThink < dt then
        self:OnIntervalThink()
    end

    if self.duration and self.elapsed >= self.duration then
        self:destroy()
    end
end

function Modifier:refresh(params)
    self.elapsed = 0
    self.stack = self.stack + 1
    self:OnRefresh(params)
end

function Modifier:destroy()
    if self.destroyed then return end
    self.destroyed = true
    self:OnDestroy()
    local owner = self.owner or self.caster
    if owner and owner.removeModifier then
        owner:removeModifier(self)
    end
end

return Modifier
