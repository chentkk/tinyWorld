-- game/scripts/vscripts/combat/ability.lua
-- Ability 基类: 统一处理 立即释放 / 施法时间 / 持续施法 三种释放流程。

local class = require "tinyworld.core.class"

local STATE = {
    READY = "ready",
    CASTING = "casting",
    CHANNELING = "channeling",
    COOLDOWN = "cooldown",
}

local Ability = class.makeClass("Ability")

function Ability:ctor(caster, data)
    self.caster = caster
    self.data = data or {}
    self.level = 1
    self.state = STATE.READY
    self.castPoint = tonumber(self.data.castPoint or self.data.AbilityCastPoint) or 0
    self.cooldownLeft = 0
    self.channelTime = tonumber(self.data.channelTime) or 0
    self.elapsed = 0
end

function Ability:GetCastRange()
    return tonumber(self.data.castRange or self.data.AbilityCastRange) or 100
end

function Ability:IsReady()
    return self.state == STATE.READY and self.cooldownLeft <= 0
end

-- 统一入口。立即释放: castPoint=0, channelTime=0
function Ability:cast(target)
    if not self:IsReady() then return false end

    self.target = target
    self.state = STATE.CASTING
    self.elapsed = 0
    self:OnCastStart()
    return true
end

function Ability:update(dt)
    if self.cooldownLeft > 0 then
        self.cooldownLeft = self.cooldownLeft - dt
        if self.cooldownLeft <= 0 then
            self.cooldownLeft = 0
            self.state = STATE.READY
        end
        return
    end

    if self.state ~= STATE.CASTING and self.state ~= STATE.CHANNELING then
        return
    end

    self.elapsed = self.elapsed + dt
    if self.state == STATE.CASTING and self.elapsed >= self.castPoint then
        self:finishCast()
        return
    end

    if self.state == STATE.CHANNELING then
        self:OnChannelThink(dt)
        if self.channelTime > 0 and self.elapsed >= self.channelTime then
            self:finishChannel()
        end
    end
end

function Ability:finishCast()
    if self.channelTime > 0 then
        self.state = STATE.CHANNELING
        self.elapsed = 0
        self:OnChannelStart()
        return
    end

    self:OnSpellStart()
    self:startCooldown()
end

function Ability:finishChannel()
    self:OnChannelFinish()
    self:startCooldown()
end

function Ability:startCooldown()
    self.cooldownLeft = tonumber(self.data.cooldown or self.data.AbilityCooldown or 1) or 1
    self.state = STATE.COOLDOWN
end

-- 技能初始化: 自动挂载被动 modifier(数据只给 modifier 名)
function Ability:initModifier()
    local passive = self.data.passiveModifier
    if type(passive) == "string" then
        self.caster:addModifier(passive, self, nil)
    end
end

-- 子类回调
function Ability:OnCastStart() end
function Ability:OnSpellStart() end
function Ability:OnChannelStart() end
function Ability:OnChannelThink(dt) end
function Ability:OnChannelFinish() end

Ability.STATE = STATE
return Ability
