-- game/components/projectile.lua
-- 投掷物运动组件。
--   * targetId: 追踪目标
--   * 无 targetId: 按 dir 直线前进
-- 命中控制:
--   * pierce=false: 命中后立刻销毁(默认)
--   * pierce=true : 命中后继续前进, 直到超距或命中数达 maxHits
-- 同一目标只触发一次 projectile_hit / OnProjectileHit。

local component = require "tinyworld.entity.component"

local Projectile = component.extend("Projectile")

local function round2(n)
    n = tonumber(n) or 0
    return math.floor(n * 100 + 0.5) / 100
end

function Projectile:ctor(entity, name)
    component.ctor(self, entity, name)
    self.traveled = 0
    self.hitSet = {}
    self.hitCount = 0
    self.destroyed = false
end

function Projectile:nearbyCells()
    local entity = self.entity
    if entity.space then
        return entity.space.cells
    end
    return { entity.cell }
end

function Projectile:findTarget()
    local entity = self.entity
    local targetId = entity:get("targetId")
    if not targetId then return nil end

    for _, cell in ipairs(self:nearbyCells()) do
        for _, candidate in pairs(cell and cell.entities or {}) do
            if candidate:getRealId() == targetId and candidate ~= entity then
                return candidate
            end
        end
    end
    return nil
end

function Projectile:direction()
    local entity = self.entity
    local target = self:findTarget()
    if target then
        return (target.x or entity.x) - entity.x, (target.y or entity.y) - entity.y
    end

    local dir = entity:get("dir") or 0
    return math.cos(dir), math.sin(dir)
end

function Projectile:targetsInRadius(radius)
    local entity = self.entity
    local out = {}
    local radius2 = radius * radius

    local ownerId = entity:get("ownerId")
    for _, cell in ipairs(self:nearbyCells()) do
        for _, candidate in pairs(cell and cell.entities or {}) do
            if candidate ~= entity
                and candidate:getRealId()
                and (not ownerId or candidate:getRealId() ~= ownerId)
                and not self.hitSet[candidate:getRealId()] then
                local dx = (candidate.x or 0) - entity.x
                local dy = (candidate.y or 0) - entity.y
                if dx * dx + dy * dy <= radius2 then
                    out[#out + 1] = candidate
                end
            end
        end
    end
    return out
end

function Projectile:onHit(hitTargets, x, y)
    local entity = self.entity

    -- ghost 命中尽量归一到真身, 避免技能对投影对象结算
    local resolved = {}
    for _, target in ipairs(hitTargets) do
        local real = target
        if target.isGhost and target.realEntity then
            real = target:realEntity() or target
        end
        if real then resolved[#resolved + 1] = real end
    end

    entity:emit("projectile_hit", {
        projectile = entity,
        ownerId = entity:get("ownerId"),
        targets = resolved,
    })

    local ability = entity.ability
    if ability and ability.OnProjectileHit then
        ability:OnProjectileHit(resolved, x, y)
    end

    for _, target in ipairs(resolved) do
        self.hitSet[target:getRealId()] = true
    end
    self.hitCount = self.hitCount + #resolved

    local tracking = entity:get("targetId") ~= nil
    if tracking then
        -- 追踪型命中即销毁
        self.destroyed = true
        entity:destroy()
        return
    end

    -- 直线型: 默认穿透, 直到超距; 显式 pierce=false 才命中销毁
    local pierce = entity:get("pierce")
    if pierce == false then
        self.destroyed = true
        entity:destroy()
    end

    if not self.destroyed then
        local maxHits = entity:get("maxHits")
        if maxHits and self.hitCount >= maxHits then
            self.destroyed = true
            entity:destroy()
        end
    end
end

function Projectile:onTick(dt)
    if self.destroyed then return end

    local entity = self.entity
    if not entity.cell then return end

    local speed = entity:get("speed") or 10
    local range = entity:get("range") or 20
    local hitRadius = entity:get("hitRadius") or 2

    local dirX, dirY = self:direction()
    local len = math.sqrt(dirX * dirX + dirY * dirY)
    if len > 0.001 then
        dirX = dirX / len
        dirY = dirY / len
    else
        dirX, dirY = 1, 0
    end

    local step = speed * dt
    self.traveled = self.traveled + step
    local outOfRange = self.traveled >= range
    if outOfRange then
        step = step - (self.traveled - range)
        self.traveled = range
    end

    entity.x = round2(entity.x + dirX * step)
    entity.y = round2(entity.y + dirY * step)

    local trackingTarget = self:findTarget()
    local hitTargets = {}

    if trackingTarget then
        local dx = trackingTarget.x - entity.x
        local dy = trackingTarget.y - entity.y
        if dx * dx + dy * dy <= hitRadius * hitRadius then
            hitTargets[#hitTargets + 1] = trackingTarget
        end
    else
        for _, candidate in ipairs(self:targetsInRadius(hitRadius)) do
            hitTargets[#hitTargets + 1] = candidate
        end
    end

    if #hitTargets > 0 then
        self:onHit(hitTargets, entity.x, entity.y)
    end

    if outOfRange and not self.destroyed then
        entity:emit("projectile_hit", {
            projectile = entity,
            ownerId = entity:get("ownerId"),
            targets = {},
        })

        local ability = entity.ability
        if ability and ability.OnProjectileHit then
            ability:OnProjectileHit({}, entity.x, entity.y)
        end

        self.destroyed = true
        entity:destroy()
    end
end

return Projectile
