-- tinyworld/combat/modifier.lua
-- Modifier 基类(dota2 风格生命周期)。
-- modifier 的 create/refresh/destroy 会通过实体事件通知上层,
-- 由上层同步系统(如 buff 视图)统一推给客户端, 战斗框架不直接处理网络。

local class = require "tinyworld.core.class"
local Object = require "tinyworld.schema.object"
local nextId = 0

local function round2(n)
    n = tonumber(n) or 0
    return math.floor(n * 100 + 0.5) / 100
end

local Modifier = Object.extend("Modifier")

function Modifier:ctor(parent, ability, params, schema)
    Object.ctor(self, schema)
    params = params or {}

    nextId = nextId + 1
    self.uid = nextId
    self.id = nextId
    self.parent = parent
    self.ability = ability
    self.caster = ability and ability.caster
    self.duration = params.duration
    self.elapsed = 0
    self.destroyed = false
    self.stack = 1
    self.remaining = round2(self.duration and self.duration or 0)
    self.intervalThink = tonumber(ability and ability.data and ability.data.intervalThink) or 0
    self._params = params
end

-- 以下生命周期回调由具体逻辑脚本覆盖
function Modifier:OnCreated(data) end
function Modifier:OnRefresh(data) end
function Modifier:OnDestroy() end
function Modifier:OnIntervalThink() end

function Modifier:GetCaster() return self.caster end
function Modifier:GetParent() return self.parent end
function Modifier:GetAbility() return self.ability end

function Modifier:GetModifierName()
    return self._name or "modifier"
end

function Modifier:IsPurgable()
    return true
end

function Modifier:update(dt)
    if self.destroyed then return end

    self.elapsed = self.elapsed + dt

    local hasDuration = self.duration and self.duration > 0
    self.remaining = round2(hasDuration and math.max(0, self.duration - self.elapsed) or 0)

    if self.intervalThink > 0 and self.elapsed % self.intervalThink < dt then
        self:OnIntervalThink()
    end

    if hasDuration and self.elapsed >= self.duration then
        self:destroy()
    end
end

function Modifier:refresh(params)
    self.elapsed = 0
    self.stack = self.stack + 1
    self.remaining = round2(self.duration and self.duration or 0)
    self:OnRefresh(params)
end

function Modifier:destroy()
    if self.destroyed then return end
    self.destroyed = true
    self:OnDestroy()
    local owner = self.owner or self.caster
    if owner then
        local modifierManager = require "tinyworld.combat.modifier_manager"
        modifierManager.removeModifier(owner, self)
    end
end

return Modifier
