-- tinyworld/space/load_balancer.lua
-- space 负载均衡。统计 cellapp 的 real entity 数量与每帧 cpu 负载,
-- cpu 负载使用指数平滑, 避免尖峰误判。
-- 策略: 1 动态分裂/合并 2 动态调整 cell 边界 3 开关 4 cell 跨 app 迁移。
-- 当前只启用 2、3, 1、4 仅实现不启用。

local class = require "tinyworld.core.class"

local LoadBalancer = class.makeClass("LoadBalancer")

function LoadBalancer:ctor(spaceConfig)
    self.config = spaceConfig
    self.stats = {} -- appId -> { realCount, cpu, smoothCpu, cells }
    self.enabled = spaceConfig.balance and spaceConfig.balance.enabled and true or false
    self.strategy = (spaceConfig.balance and spaceConfig.balance.strategy) or 2
    self.migrateInProgress = {} -- 防抖: app 对迁移冷却
end

function LoadBalancer:report(appId, realCount, cpu, cells)
    local st = self.stats[appId]
    if not st then
        st = { realCount = 0, cpu = 0, smoothCpu = 0, cells = {} }
        self.stats[appId] = st
    end

    st.realCount = realCount
    st.rawCpu = cpu
    -- 指数平滑: alpha=0.2, 防止上次 10% 本次 90% 直接判 90%
    if st.smoothCpu == 0 then
        st.smoothCpu = cpu
    else
        st.smoothCpu = st.smoothCpu * 0.8 + cpu * 0.2
    end
    st.cells = cells or {}
    return st.smoothCpu
end

function LoadBalancer:isEnabled()
    return self.enabled and (self.strategy == 2)
end

-- 策略 2: 根据负载调整 cell 边界。此处返回建议的 cellSize 调整量。
-- 简单实现: 平均平滑负载过高时放大 cellSize(减少 cell) 或缩小(增加 cell)。
function LoadBalancer:computeBoundaryAdvice()
    local sum, n = 0, 0
    for _, st in pairs(self.stats) do
        sum = sum + st.smoothCpu
        n = n + 1
    end
    if n == 0 then return 0 end

    local avg = sum / n
    if avg > 0.8 then return 1 end
    if avg < 0.35 then return -1 end
    return 0
end

-- 策略 1: 动态分裂 / 合并 (当前不启用, 仅实现接口)
function LoadBalancer:trySplitMerge()
    return nil
end

-- 策略 4: 高负载 cellapp 的 cell 迁往低负载。带防抖, 避免迁移后负载反转不断迁移。
function LoadBalancer:tryMigrateCell()
    if self.strategy ~= 4 then return nil end

    local high, low
    for appId, st in pairs(self.stats) do
        if not high or st.smoothCpu > high.st.smoothCpu then high = { appId = appId, st = st } end
        if not low or st.smoothCpu < low.st.smoothCpu then low = { appId = appId, st = st } end
    end
    if not high or not low or high == low then return nil end

    local diff = high.st.smoothCpu - low.st.smoothCpu
    if diff < 0.3 then return nil end

    -- 防抖: 迁移后双方平滑负载趋近, 若近期迁移过则忽略
    local key = high.appId .. ":" .. low.appId
    local now = os.time()
    if self.migrateInProgress[key] and now - self.migrateInProgress[key] < 5 then
        return nil
    end

    self.migrateInProgress[key] = now
    local cell = high.st.cells[1]
    return cell and { from = high.appId, to = low.appId, cell = cell } or nil
end

function LoadBalancer:tick()
    if not self:isEnabled() then
        self:trySplitMerge()
        return nil
    end
    return self:computeBoundaryAdvice()
end

return LoadBalancer
