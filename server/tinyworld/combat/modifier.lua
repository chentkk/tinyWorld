-- tinyworld/combat/modifier.lua
-- Modifier 基类(dota2 风格生命周期)。
-- modifier 的 create/refresh/destroy 会通过实体事件通知上层,
-- 由上层同步系统(如 buff 视图)统一推给客户端, 战斗框架不直接处理网络。
--
-- 重要: modifier 只保存可序列化的纯状态, 不持有 ability / caster 等动态对象。
-- 迁移时来源 ability 乃至 caster 实体都可能已不存在, 因此重建只能依赖这些状态。

local class = require "tinyworld.core.class"
local Object = require "tinyworld.schema.object"
local nextId = 0

local function round2(n)
    n = tonumber(n) or 0
    return math.floor(n * 100 + 0.5) / 100
end

local function orDefault(value, default)
    if value == nil then return default end
    return value
end

local Modifier = Object.extend("Modifier")

-- params: { casterId, abilityName, duration, intervalThink, elapsed, stack }
function Modifier:ctor(parent, params, schema)
    Object.ctor(self, schema)

    assert(parent, "Modifier: parent/owner required")
    params = params or {}

    nextId = nextId + 1
    self.uid = nextId
    self.id = nextId
    self.parent = parent

    self.name = self._name or "modifier"
    self.casterId = params.casterId
    self.abilityName = params.abilityName
    self.duration = params.duration or 0
    self.intervalThink = tonumber(params.intervalThink) or 0
    self.elapsed = tonumber(params.elapsed) or 0
    self.destroyed = false
    self.stack = orDefault(params.stack, 1)
    self.remaining = round2(self.duration - self.elapsed)
    self._params = params
end

-- 从已有的来源 ability 构造参数(仅创建时使用, 不保存 ability 引用)
function Modifier.buildParams(ability, params)
    assert(ability, "Modifier.buildParams: ability required")
    assert(ability.caster and ability.caster.getRealId, "Modifier.buildParams: ability caster required")

    params = params or {}
    return {
        casterId = ability.caster:getRealId(),
        abilityName = ability:GetAbilityName(),
        duration = params.duration,
        intervalThink = tonumber(ability.data and ability.data.intervalThink) or 0,
    }
end

-- 统一构造入口(类方法): modifier 只依赖可序列化的纯状态, 不依赖来源 ability
-- 或 caster 对象(迁移时二者都可能已不存在)。
--   * 迁移/加载: data 为序列化状态(含 id/name), 按 data.name 还原具体子类并恢复 uid;
--   * 业务创建: data 由 Modifier.buildParams(ability, params) 派生(无 id, 分配新 uid)。
-- 两类调用最终都走 cls.new(parent, params, schema)。
function Modifier.fromData(container, data)
    data = data or {}
    assert(container.host, "Modifier.fromData: container has no host")

    local cls = (data.name and _G[data.name]) or Modifier
    local mod = cls.new(container.host, {
        casterId = data.casterId,
        abilityName = data.abilityName,
        duration = data.duration,
        intervalThink = data.intervalThink,
        elapsed = data.elapsed,
        stack = data.stack,
    }, container.def.childSchema)

    -- 恢复原始 uid, 保证 view:remove(mod.uid) 与入库 key 一致
    if data.id ~= nil then mod.uid = data.id end
    return mod
end

-- 以下生命周期回调由具体逻辑脚本覆盖
function Modifier:OnCreated(data) end
function Modifier:OnRefresh(data) end
function Modifier:OnDestroy() end
function Modifier:OnIntervalThink() end

-- caster 只在宿主所在 cell 内按 realId 查找, 可能是 real 或 ghost; 不存在则返回 nil
function Modifier:GetCaster()
    local cell = self.parent and self.parent.cell
    return cell and cell:findByRealId(self.casterId)
end

function Modifier:GetParent()
    return self.parent
end

function Modifier:GetModifierName()
    return self.name
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
    local owner = self.owner or self:GetCaster()
    if owner then
        local modifierManager = require "tinyworld.combat.modifier_manager"
        modifierManager.removeModifier(owner, self)
    end
end

return Modifier
