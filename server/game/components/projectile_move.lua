-- game/components/projectile_move.lua
-- 投掷物运动组件。同 cell 内直线前进或追目标, 命中后只发 projectile_hit 事件,
-- 具体效果由游戏层监听事件处理, 投掷物随后销毁。

local component = require "tinyworld.entity.component"

local ProjectileMove = component.extend("ProjectileMove")

function ProjectileMove:ctor(entity, name)
    component.ctor(self, entity, name)
    self.traveled = 0
    self.startX = entity.x
    self.startY = entity.y
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

function ProjectileMove:onTick(dt)
    if self.destroyed then return end

    local entity = self.entity
    if not entity.cell then return end

    local speed = entity:get("speed") or 10
    local range = entity:get("range") or 20
    local hitRadius = entity:get("hitRadius") or 2

    local target = self:findTarget()
    local dirX, dirY
    if target then
        dirX = (target.x or entity.x) - entity.x
        dirY = (target.y or entity.y) - entity.y
    else
        local dir = entity:get("dir") or 0
        dirX = math.cos(dir)
        dirY = math.sin(dir)
    end

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

    local hitTarget = nil
    if target then
        local dx = target.x - entity.x
        local dy = target.y - entity.y
        if dx * dx + dy * dy <= hitRadius * hitRadius then
            hitTarget = target
        end
    end

    if hitTarget or outOfRange then
        self.destroyed = true
        entity:emit("projectile_hit", {
            projectile = entity,
            ownerId = entity:get("ownerId"),
            targetId = hitTarget and hitTarget.clientId or nil,
        })
        entity:destroy()
    end
end

return ProjectileMove
