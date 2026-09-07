-- tinyworld/combat/projectile.lua
-- 通用战斗实体组件(类型名沿用 Projectile, 语义为可运动/静止的战斗实体):
--   运动(movement): "none" / "linear" / "homing" / "wander"
--   生命周期: duration / range
--   行为: onHit / onIntervalThink / selectTarget / onDestroy(经 runtime 配置)
-- 行为全部由使用层提供; 组件只负责运动、候选选择、生命周期与回调调度。

local component = require "tinyworld.entity.component"

local Projectile = component.extend("Projectile")

local function round2(n)
    n = tonumber(n) or 0
    return math.floor(n * 100 + 0.5) / 100
end

-- 目标是否存活
local function targetAlive(t)
    if not t then return false end
    if t:get("hp") then
        return t:get("hp") > 0
    end
    return true
end

-- 目标是否为合法目标
-- 默认排除: 自身 / owner / 不可被选为目标的对象(not_targetable tag)
-- 如果有 hp 属性, 默认还排除死亡目标。使用层可用 runtime.targetFilter 覆盖/追加过滤。
local function targetValid(entity, t, runtime)
    if not t or t == entity or not t:getRealId() then return false end

    -- 对象分类: 不选带 not_targetable 标签的对象(如 projectile / server_object)
    if t:hasTag("not_targetable") then return false end

    if t:get("hp") then
        if t:get("hp") <= 0 then return false end
    end

    local ownerId = entity:get("ownerId")
    if ownerId and t:getRealId() == ownerId then return false end

    if runtime.targetFilter then
        local ok = runtime.targetFilter(entity, t)
        assert(type(ok) == "boolean", "targetFilter must return boolean")
        return ok
    end
    return true
end

function Projectile:ctor(entity, name)
    component.ctor(self, entity, name)

    self.traveled = 0
    self.hitSet = {}
    self.hitCount = 0
    self.destroyed = false
    self.elapsed = 0
    self.tickIndex = 0
    self.wanderDir = nil

    -- Projectile 必须通过 projectileManager.Create(或显式 runtime)创建;
    -- runtime 是行为/运动配置, 缺失属于配置错误, 不能用静默 fallback 吞掉。
    local runtime = rawget(entity, "runtime")
    assert(runtime, "Projectile requires runtime (create via projectileManager)")
    self.runtime = runtime
end

-- 运动方式必须显式配置, 不允许推断(fallback 会隐藏配置遗漏)
function Projectile:movementMode()
    local movement = self.runtime.movement
    assert(movement, "Projectile runtime.movement is required")
    return movement
end

-- 仅当前 cell。理由:
--   * 战斗实体是短生命周期对象(migratable=false), 运行距离有限;
--   * ghostRange 是 aoiRange 的 2 倍, 跨边界目标通常在当前 cell 已有 ghost;
--   * 因此判断当前 cell 对象即可覆盖绝大多数场景;
--   * 后续若出现边界误判, 再扩展为"当前 cell + 自己 ghost 覆盖的 cell"。
function Projectile:nearbyCells()
    return { self.entity.cell }
end

function Projectile:findTarget()
    local entity = self.entity
    local targetId = entity:get("targetId")
    if not targetId then return nil end

    -- 先查当前 cell
    local current = entity.cell
    local candidate = current and current:findByRealId(targetId)
    if candidate and candidate ~= entity and targetAlive(candidate) then
        return candidate
    end

    -- 追踪目标有明确 id, 当前 cell 找不到时按本地 space 的 cell 索引兜底;
    -- space 是 cell 实体的上下文, 不存在说明对象尚未入 space, 应显式抛错
    assert(entity.space, "Projectile requires space for target lookup")
    for _, cell in ipairs(entity.space.cells) do
        if cell ~= current then
            local c = cell:findByRealId(targetId)
            if c and c ~= entity and targetAlive(c) then
                return c
            end
        end
    end
    return nil
end

-- 默认目标选择策略: 最近的合法目标(供 selectTarget 未提供时使用)
function Projectile:selectNearestTarget()
    local entity = self.entity
    local cell = assert(entity.cell, "Projectile not bound to a cell")
    assert(cell.spatial, "cell has no spatial index")

    local best, bestDist
    local seen = {}
    for _, candidate in ipairs(cell.spatial:query(entity.x, entity.y)) do
        if candidate ~= entity then
            local rid = candidate:getRealId()
            if rid and not seen[rid] and self:targetValid(candidate) then
                seen[rid] = true
                local dx = candidate.x - entity.x
                local dy = candidate.y - entity.y
                local d = dx * dx + dy * dy
                if not best or d < bestDist then
                    best, bestDist = candidate, d
                end
            end
        end
    end
    return best
end

-- 附近合法目标(供使用层 selectTarget 等使用)
function Projectile:getNearbyTargets(dist)
    local entity = self.entity
    local cell = assert(entity.cell, "Projectile not bound to a cell")
    assert(cell.spatial, "cell has no spatial index")

    local out = {}
    local seen = {}
    for _, candidate in ipairs(cell.spatial:query(entity.x, entity.y, dist)) do
        if candidate ~= entity then
            local rid = candidate:getRealId()
            if rid and not seen[rid] and self:targetValid(candidate) then
                seen[rid] = true
                out[#out + 1] = candidate
            end
        end
    end
    return out
end

function Projectile:selectTarget(oldTargetId)
    local runtime = self.runtime
    if runtime.selectTarget then
        local id = runtime.selectTarget(self.entity, oldTargetId)
        if id then return id end
        return nil
    end

    -- 默认策略: 最近的合法目标(显式可选)
    local nearest = self:selectNearestTarget()
    if nearest then return nearest:getRealId() end
    return nil
end

function Projectile:targetValid(t)
    return targetValid(self.entity, t, self.runtime)
end

function Projectile:targetsInRadius(radius)
    local entity = self.entity
    local cell = assert(entity.cell, "Projectile not bound to a cell")
    assert(cell.spatial, "cell has no spatial index")

    local out = {}
    local seen = {}
    for _, candidate in ipairs(cell.spatial:query(entity.x, entity.y, radius)) do
        if candidate ~= entity then
            local rid = candidate:getRealId()
            if rid and not seen[rid] and self:targetValid(candidate) then
                seen[rid] = true
                out[#out + 1] = candidate
            end
        end
    end
    return out
end

-- 命中: 使用层 onHit 决定后续; 组件只负责候选与 dedupe
function Projectile:resolveHits(list, x, y)
    local entity = self.entity
    local runtime = self.runtime
    local dedupe = runtime.dedupe or "entity" -- 可选策略, 缺省 entity

    local resolved = {}
    local sameTickSeen = {}
    for _, t in ipairs(list) do
        local rid = t:getRealId()
        if not sameTickSeen[rid] and not (dedupe == "entity" and self.hitSet[rid]) then
            sameTickSeen[rid] = true
            resolved[#resolved + 1] = t
        end
    end

    if #resolved == 0 then return "keep" end

    if runtime.onHit then
        local result = runtime.onHit(entity, resolved, x, y)
        if result == "destroy" then
            return "destroy"
        end
    end

    if dedupe ~= "none" then
        for _, t in ipairs(resolved) do
            self.hitSet[t:getRealId()] = true
        end
    end
    self.hitCount = self.hitCount + #resolved

    return "keep"
end

function Projectile:intervalThink()
    local entity = self.entity
    local runtime = self.runtime

    local areaRadius = entity:get("areaRadius") or entity:get("hitRadius")
    local targets = self:targetsInRadius(areaRadius)

    if runtime.onIntervalThink then
        runtime.onIntervalThink(entity, targets, self.tickIndex)
    end

    self.tickIndex = self.tickIndex + 1
end

function Projectile:move(dt)
    local entity = self.entity
    local speed = entity:get("speed")
    local mode = self:movementMode()

    if mode == "none" then
        return
    end

    if mode == "linear" then
        local dir = entity:get("dir")
        entity.x = round2(entity.x + math.cos(dir) * speed * dt)
        entity.y = round2(entity.y + math.sin(dir) * speed * dt)
        return
    end

    if mode == "homing" then
        local target = self:findTarget()
        if not target then
            local newId = self:selectTarget(entity:get("targetId"))
            if newId and newId ~= entity:get("targetId") then
                entity:set("targetId", newId)
            end
            return
        end

        local dx = target.x - entity.x
        local dy = target.y - entity.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.001 then
            entity.x = round2(entity.x + dx / len * speed * dt)
            entity.y = round2(entity.y + dy / len * speed * dt)
        end
        return
    end

    if mode == "wander" then
        if not self.wanderDir or math.random() < 0.1 then
            self.wanderDir = math.random() * 2 * math.pi
        end
        entity.x = round2(entity.x + math.cos(self.wanderDir) * speed * dt)
        entity.y = round2(entity.y + math.sin(self.wanderDir) * speed * dt)
        return
    end

    -- 未知 movement 视为静止
end

function Projectile:onTick(dt)
    if self.destroyed then return end

    local entity = self.entity
    if not entity.cell then return end

    local runtime = self.runtime

    -- 1) 运动
    self:move(dt)

    -- 2) traveled 累计(movement 为 none 时无 range 语义)
    local mode = self:movementMode()
    if mode ~= "none" then
        local speed = entity:get("speed")
        self.traveled = self.traveled + speed * dt
    end

    -- 3) 先推进 elapsed, 保证 duration 边界 tick 也能触发周期行为
    self.elapsed = self.elapsed + dt

    -- 4) 周期行为
    local interval = entity:get("tickInterval")
    if interval and interval > 0 then
        local want = math.floor(self.elapsed / interval + 1e-9)
        while self.tickIndex < want and not self.destroyed do
            self:intervalThink()
        end
    end

    -- 5) 命中判定(运动型才有碰撞语义)
    if mode ~= "none" and not self.destroyed then
        local hitRadius = entity:get("hitRadius")
        local targets
        if mode == "homing" then
            local t = self:findTarget()
            targets = t and { t } or {}
        else
            targets = self:targetsInRadius(hitRadius)
        end

        if #targets > 0 then
            local verdict = self:resolveHits(targets, entity.x, entity.y)
            if verdict == "destroy" then
                self:destroy()
                return
            end
        end
    end

    -- 6) 生命周期
    local duration = entity:get("duration")
    if duration and self.elapsed >= duration then
        self:destroy()
        return
    end

    local range = entity:get("range")
    if range and self.traveled >= range then
        self:destroy()
        return
    end
end

function Projectile:destroy()
    if self.destroyed then return end
    self.destroyed = true

    local runtime = self.runtime
    if runtime.onDestroy then
        runtime.onDestroy(self.entity)
    end

    self.entity:destroy()
end

return Projectile
