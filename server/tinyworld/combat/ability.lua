-- tinyworld/combat/ability.lua
-- Ability 基类: 统一处理 立即释放 / 施法时间 / 持续施法 三种释放流程。

local class = require "tinyworld.core.class"
local Object = require "tinyworld.schema.object"

local function round2(n)
    n = tonumber(n) or 0
    return math.floor(n * 100 + 0.5) / 100
end

local STATE = {
    READY = "ready",
    CASTING = "casting",
    CHANNELING = "channeling",
    COOLDOWN = "cooldown",
}

local Ability = Object.extend("Ability")

-- 反序列化工厂(类方法): Ability 的宿主(caster)必须存在, 技能行为依赖 npc 数据,
-- 因此按 data.id(技能名)经 ability_loader 重建实例; caster 即容器宿主实体。
-- (ability 的宿主一定存在, 与 modifier 不同: modifier 的来源 ability 可能已消失)
function Ability.fromData(container, data)
    local abilityLoader = require "tinyworld.combat.ability_loader"
    local name = assert(data and data.id, "Ability.fromData: data.id required")
    local caster = assert(container.host, "Ability.fromData: container has no host")
    return assert(abilityLoader.createAbility(caster, name),
        "Ability.fromData: unknown ability " .. tostring(name))
end

function Ability:ctor(caster, data, schema)
    Object.ctor(self, schema)
    self.caster = caster
    self.data = data or {}
    self.id = self:GetAbilityName()
    self.level = 1
    self.state = STATE.READY
    self.castPoint = tonumber(self:GetSpecialValueFor("AbilityCastPoint")) or 0
    self.cooldownLeft = 0
    self.channelTime = tonumber(self:GetSpecialValueFor("channelTime")) or 0
    self.elapsed = 0
end

function Ability:GetCaster()
    return self.caster
end

function Ability:GetCursorTarget()
    return self.target
end

function Ability:GetAbilityName()
    return self.data and self.data.name
end

function Ability:GetSpecialValueFor(key)
    return self.data and self.data[key]
end

function Ability:GetCastRange()
    return tonumber(self:GetSpecialValueFor("AbilityCastRange")) or 100
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
        self.cooldownLeft = round2(self.cooldownLeft - dt)
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
    self.cooldownLeft = tonumber(self:GetSpecialValueFor("AbilityCooldown")) or 1
    self.state = STATE.COOLDOWN
end

-- example: 被动/自带 modifier 由技能 GetIntrinsicModifierName 声明,
-- 创建 ability 时系统自动挂载, 不从 npc 数据读取。
function Ability:GetIntrinsicModifierName()
    return nil
end

function Ability:initModifier()
    local name = self:GetIntrinsicModifierName()
    if type(name) == "string" then
        local modifierManager = require "tinyworld.combat.modifier_manager"
        modifierManager.addModifier(self.caster, name, self, nil)
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
