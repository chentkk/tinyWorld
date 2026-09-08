-- tinyworld/app/cellapp/timer_scheduler.lua
-- entity 级定时器调度器。
-- 底层时间轮只负责"一次性到期"；有限次/无限次的重复调度由本 Lua 层负责:
--   每次到期后, 如果还有剩余次数(或无限), 就重新 add 一个一次性的到期。
-- timer id 以 entity realId 前缀生成, 因此同一个 entity 迁移到其他 cell 时
-- timer id 不会与其他 entity 冲突, 也便于 take / adopt 整体迁移。
-- 接口:
--   s = TimerScheduler.new()
--   id = s:add(entity, delay, times, fn)
--   s:remove(id)
--   s:update(deltaSec)
--   entries, ids = s:take(entityId)
--   s:adopt(promoted, entries)

local class = require "tinyworld.core.class"

local TimerScheduler = class.makeClass("TimerScheduler")

-- 时间轮由 C 模块提供(luaclib/timerwheel.so), 单位毫秒。
local Wheel = require "timerwheel"

function TimerScheduler:ctor()
    self.wheel = Wheel.new()
    self.timers = {}      -- id -> {entity, delaySec, remain, fn, id}
    self.byEntity = {}    -- entityId -> { id=true }
    self.nextId = 0
end

function TimerScheduler:add(entity, delay, times, fn)
    assert(entity and entity.id, "TimerScheduler.add: entity required")
    assert(type(delay) == "number", "TimerScheduler.add: numeric delay required")
    assert(type(fn) == "function", "TimerScheduler.add: callback required")

    local count = times
    if count == nil then count = 1 end
    if count == 0 then count = 1 end
    if count < 0 then count = -1 end

    local entityId = tostring(entity:getRealId())
    self.nextId = self.nextId + 1
    local id = self.nextId

    self.timers[id] = {
        id = id,
        entity = entity,
        entityId = entityId,
        delaySec = delay,
        count = count,
        remain = count,   -- -1 表示无限
        fn = fn,
        removed = false,
    }
    self.byEntity[entityId] = self.byEntity[entityId] or {}
    self.byEntity[entityId][id] = true

    self.wheel:add(id, math.floor(delay * 1000))
    return id
end

function TimerScheduler:remove(id)
    local timer = self.timers[id]
    if not timer or timer.removed then return false end

    timer.removed = true
    self.timers[id] = nil
    if self.byEntity[timer.entityId] then
        self.byEntity[timer.entityId][id] = nil
    end
    self.wheel:remove(id)
    return true
end

-- 清除某实体所有定时器(实体离开 cell / 迁移离开时调用)
function TimerScheduler:clearEntity(entityId)
    entityId = tostring(entityId)
    local list = self.byEntity[entityId] or {}
    for id in pairs(list) do
        self.wheel:remove(id)
        self.timers[id] = nil
    end
    self.byEntity[entityId] = nil
end

-- 取出某个实体所有定时器(迁移时用), 返回 entries 数组
function TimerScheduler:take(entityId)
    entityId = tostring(entityId)
    local list = self.byEntity[entityId] or {}
    local entries = {}
    for id in pairs(list) do
        local timer = self.timers[id]
        if timer and not timer.removed then
            timer.removed = true
            self.wheel:remove(id)
            entries[#entries + 1] = timer
            self.timers[id] = nil
        end
    end
    self.byEntity[entityId] = nil
    return entries
end

-- 目标 cell 接管 entries(本地迁移后, entity 是 promoted 新实体)
function TimerScheduler:adopt(promoted, entries)
    assert(promoted and promoted.id, "TimerScheduler.adopt: promoted entity required")
    local entityId = tostring(promoted:getRealId())
    local list = self.byEntity[entityId] or {}
    self.byEntity[entityId] = list

    for _, timer in ipairs(entries or {}) do
        assert(not self.timers[timer.id], "timer id conflict on adopt: " .. tostring(timer.id))
        timer.entity = promoted
        timer.entityId = entityId
        timer.removed = false
        self.timers[timer.id] = timer
        list[timer.id] = true
        if type(timer.id) == "number" and timer.id > (self.nextId or 0) then
            self.nextId = timer.id
        end

        -- 迁移过程中可能已经过去了一些时间, 这里按完整 delay 重新排一次;
        -- 更精确的剩余时间保持需要底层 wheel 支持, 暂不引入复杂度。
        self.wheel:add(timer.id, math.floor(timer.delaySec * 1000))
    end
end

-- 每帧一次把 deltaMs 交给底层时间轮, 一次取出全部到期 id, 不再 1ms 逐格轮询。
function TimerScheduler:update(deltaSec)
    local deltaMs = math.floor(deltaSec * 1000)
    if deltaMs <= 0 then return end
    if not next(self.timers) then return end

    local due = self.wheel:update(deltaMs)
    self:applyDue(due)
end

-- 兼容旧的 step 测试/调用: 步进 1ms
function TimerScheduler:step()
    local due = self.wheel:update(1)
    self:applyDue(due)
end

function TimerScheduler:applyDue(due)
    for _, id in ipairs(due) do
        local timer = self.timers[id]
        if not timer then
            -- 已删除
        elseif timer.removed then
            self.timers[id] = nil
        else
            if timer.remain > 0 then
                timer.remain = timer.remain - 1
            end

            local remain = timer.remain
            timer.fn(timer.entity, id, remain)

            if remain == -1 or remain > 0 then
                self.wheel:add(id, math.floor(timer.delaySec * 1000))
            else
                self.timers[id] = nil
                self.byEntity[timer.entityId][id] = nil
            end
        end
    end
end

return TimerScheduler
