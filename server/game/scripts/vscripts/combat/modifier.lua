-- game/scripts/vscripts/combat/modifier.lua
-- Modifier 基类(dota2 风格生命周期)。由 ability 施加到单位上,
-- 修改属性通过 PropertySchema 完成, 变更是自动同步的。

local class = require "tinyworld.core.class"
local M = {}

local Modifier = class.makeClass("Modifier")

function Modifier:ctor(caster, ability, duration)
    self.caster = caster
    self.ability = ability
    self.duration = duration
    self.elapsed = 0
    self.destroyed = false
end

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
    if self.OnIntervalThink then
        self:OnIntervalThink()
    end

    if self.duration and self.elapsed >= self.duration then
        self:destroy()
    end
end

function Modifier:destroy()
    if self.destroyed then return end
    self.destroyed = true
    self:OnDestroy()
    if self.caster and self.caster.removeModifier then
        self.caster:removeModifier(self)
    end
end

M.Modifier = Modifier
return M
