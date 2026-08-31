-- game/components/projectile_move.lua
-- 投掷物运动组件。
--   * 有 targetId: 追踪指定目标, 命中单一目标
--   * 无 targetId: 按 dir 直线前进, 沿途用 hitRadius 检测候选目标集合
-- 命中/超距后只发 projectile_hit 事件, 具体效果由游戏层监听处理。

local component = require "tinyworld.entity.component"

local ProjectileMove = component.extend("ProjectileMove")

function ProjectileMove:ctor(entity, name)
    component.ctor(self, entity, name)
    self.traveled = 0
    self.destroyed = false
end

function ProjectileMove:findTarget()
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

function ProjectileMove:direction()
    local entity = self.entity
    local target = self:findTarget()
    if target then
        local dx = (target.x or entity.x) - entity.x
        local dy = (target.y or entity.y) - entity.y
        return dx, dy
    end

    local dir = entity:get("dir") or 0
    return math.cos(dir), math.sin(dir)
end

-- 方向模式: 返回当前碰撞半径内的目标集合
function ProjectileMove:targetsInRadius(radius)
    local entity = self.entity
    local out = {}
    local radius2 = radius * radius

    local entities = entity.cell and entity.cell.entities or {}
    for _, candidate in pairs(entities) do
        if candidate ~= entity and candidate.clientId then
            local dx = (candidate.x or 0) - entity.x
            local dy = (candidate.y or 0) - entity.y
            if dx * dx + dy * dy <= radius2 then
                out[#out + 1] = candidate
            end
        end
    end
    return out
end

function ProjectileMove:onTick(dt)
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

    local target = self:findTarget()
    local targetId = nil
    local targets = nil

    if target then
        local dx = target.x - entity.x
        local dy = target.y - entity.y
        if dx * dx + dy * dy <= hitRadius * hitRadius then
            targetId = target.clientId
        end
    else
        targets = {}
        for _, candidate in ipairs(self:targetsInRadius(hitRadius)) do
            targets[#targets + 1] = candidate.clientId
        end
    end

    if targetId or outOfRange or (targets and #targets > 0) then
        self.destroyed = true
        entity:emit("projectile_hit", {
            projectile = entity,
            ownerId = entity:get("ownerId"),
            targetId = targetId,
            targets = targets or {},
        })
        entity:destroy()
    end
end

return ProjectileMove
