-- tinyworld/combat/projectile_manager.lua
-- 投掷物管理工具(战斗层)。技能脚本用它创建投掷物;
-- 命中结果由 framework 回调 ability:OnProjectileHit, 具体技能决定效果。

local M = {}

local function baseState(source, target)
    return {
        x = source.x or 0,
        y = source.y or 0,
        ownerId = source.clientId or source.id,
        targetId = target and (target.clientId or target.id) or nil,
    }
end

function M.CreateTrackingProjectile(params)
    local source = params.Source
    local state = baseState(source, params.Target)

    return source:spawnProjectile("Projectile", {
        props = {
            x = state.x,
            y = state.y,
            ownerId = state.ownerId,
            targetId = state.targetId,
            speed = params.iMoveSpeed or 10,
            range = params.range or 20,
            hitRadius = params.hitRadius or 2,
            pierce = params.pierce or false,
            maxHits = params.maxHits,
        },
        ability = params.Ability,
    })
end

function M.CreateLinearProjectile(params)
    local source = params.Source
    local state = baseState(source, nil)

    return source:spawnProjectile("Projectile", {
        props = {
            x = state.x,
            y = state.y,
            ownerId = state.ownerId,
            targetId = nil,
            dir = params.dir or 0,
            speed = params.iMoveSpeed or 10,
            range = params.range or 20,
            hitRadius = params.hitRadius or 2,
            pierce = params.pierce or false,
            maxHits = params.maxHits,
        },
        ability = params.Ability,
    })
end

return M
