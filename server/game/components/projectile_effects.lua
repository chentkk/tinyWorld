-- game/components/projectile_effects.lua
-- 投掷物命中效果组件: 监听 projectile_hit, 若投掷物配置了 damage 则结算伤害。
-- 不做任何其他效果, 保持命中效果可扩展。

local component = require "tinyworld.entity.component"
local combatDamage = require "tinyworld.combat.damage"

local ProjectileEffects = component.extend("ProjectileEffects")

function ProjectileEffects:onCreate()
    self.entity:on("projectile_hit", function(_, data)
        self:onHit(data or {})
    end)
end

function ProjectileEffects:findEntityById(id)
    local cell = self.entity.cell
    for _, candidate in pairs(cell and cell.entities or {}) do
        if candidate.clientId == id then return candidate end
    end
    return nil
end

function ProjectileEffects:onHit(data)
    local entity = self.entity
    local damage = entity:get("damage")
    if not damage or damage <= 0 then return end

    local owner = data.ownerId and self:findEntityById(data.ownerId) or entity
    local damageType = entity:get("damageType") or combatDamage.DAMAGE_TYPE.MAGICAL

    local targets = {}
    if data.targetId then
        targets[#targets + 1] = data.targetId
    else
        for _, id in ipairs(data.targets or {}) do
            targets[#targets + 1] = id
        end
    end

    for _, targetId in ipairs(targets) do
        local target = self:findEntityById(targetId)
        if target then
            combatDamage.dealDamage(owner, target, damage, damageType, nil)
        end
    end
end

return ProjectileEffects
