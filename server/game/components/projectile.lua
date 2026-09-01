-- game/components/projectile.lua
-- 投掷物运动组件。
--   * 有 targetId: 追踪单一目标
--   * 无 targetId: 按 dir 直线前进, hitRadius 检测沿途候选目标
-- 命中/超距后调用 Ability:OnProjectileHit(目标, 落点), 效果由具体技能决定。

local component = require "tinyworld.entity.component"

local Projectile = component.extend("Projectile")

function Projectile:ctor(entity, name)
    component.ctor(self, entity, name)
    self.traveled = 0
    self.destroyed = false
end

function Projectile:findTarget()
    local entity = self.entity
    local targetId = entity:get("targetId")
    if not targetId then return nil end

    local entities = entity.cell and entity.cell.entities or {}
    for _, candidate in pairs(entities) do
        if candidate.clientId == targetId and candidate ~= entity then
            return candidate
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

    local entities = entity.cell and entity.cell.entities or {}
    local ownerId = entity:get("ownerId")
    for _, candidate in pairs(entities) do
        if candidate ~= entity
            and candidate.clientId
            and (not ownerId or candidate.clientId ~= ownerId) then
            local dx = (candidate.x or 0) - entity.x
            local dy = (candidate.y or 0) - entity.y
            if dx * dx + dy * dy <= radius2 then
                out[#out + 1] = candidate
            end
        end
    end
    return out
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

    entity.x = entity.x + dirX * step
    entity.y = entity.y + dirY * step

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

    if #hitTargets > 0 or outOfRange then
        self.destroyed = true

        -- 命中事件(目标可空)
        entity:emit("projectile_hit", {
            projectile = entity,
            ownerId = entity:get("ownerId"),
            targets = hitTargets,
        })

        -- 把命中回调交给具体技能
        local ability = entity.ability
        if ability and ability.OnProjectileHit then
            ability:OnProjectileHit(hitTargets, entity.x, entity.y)
        end

        entity:destroy()
    end
end

return Projectile
