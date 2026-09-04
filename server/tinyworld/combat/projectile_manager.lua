-- tinyworld/combat/projectile_manager.lua
-- 通用战斗实体创建工具(投掷物/区域/召唤物统一入口)。
-- 使用层通过 params 传运动方式、生命周期与行为回调;
-- 同时保留 CreateLinearProjectile / CreateTrackingProjectile
-- 这类高辨识度封装, 内部统一走 Create。

local combatDamage = require "tinyworld.combat.damage"

local M = {}

local function baseState(source, target)
    return {
        x = source.x,
        y = source.y,
        ownerId = source:getRealId(),
        targetId = (target and target:getRealId()) or nil,
    }
end

-- 把内置 damage option 包装成 onHit; defaultVerdict 用于控制命中后销毁策略
local function wrapDamage(source, amount, dmgType, ability, defaultVerdict)
    if not amount then return nil, nil end

    local function apply(entity, targets)
        for _, t in ipairs(targets or {}) do
            combatDamage.dealDamage(source, t, amount, dmgType, ability)
        end
    end

    return function(entity, targets, x, y)
        apply(entity, targets)
        return defaultVerdict
    end, apply
end

-- 把内置 tickDamage option 包装成 onIntervalThink
local function wrapTickDamage(source, amount, dmgType, ability)
    if not amount then return nil end

    return function(entity, targets, tickIndex)
        for _, t in ipairs(targets or {}) do
            combatDamage.dealDamage(source, t, amount, dmgType, ability)
        end
    end
end

-- 统一创建入口
function M.Create(params)
    assert(params and params.Source, "Create: Source required")
    local source = params.Source
    local ability = params.Ability
    assert(params.movement, "Create: movement is required (none/linear/homing/wander)")

    local state = baseState(source, params.Target)
    local movement = params.movement

    -- 碰撞行为: 使用层 onHit > 内置 damage; 二者都传则先跑内置再跑使用层
    local onHit
    local dmgOpt = params.damage
    if dmgOpt then
        -- 内置 damage 的默认销毁策略: homing 命中即销毁, 其他运动方式保持飞行
        local defaultVerdict = (movement == "homing") and "destroy" or "keep"
        local builtin = wrapDamage(source, dmgOpt.amount, dmgOpt.type, ability, defaultVerdict)
        if params.onHit then
            onHit = function(entity, targets, x, y)
                builtin(entity, targets, x, y)
                return params.onHit(entity, targets, x, y)
            end
        else
            onHit = builtin
        end
    else
        onHit = params.onHit
    end

    -- 周期行为: 使用层 onIntervalThink > 内置 tickDamage; 都传则组合
    local onIntervalThink
    local tickOpt = params.tickDamage
    if tickOpt then
        local builtinTick = wrapTickDamage(source, tickOpt.amount, tickOpt.type, ability)
        if params.onIntervalThink then
            onIntervalThink = function(entity, targets, tickIndex)
                builtinTick(entity, targets, tickIndex)
                return params.onIntervalThink(entity, targets, tickIndex)
            end
        else
            onIntervalThink = builtinTick
        end
    else
        onIntervalThink = params.onIntervalThink
    end

    -- runtime 只承载行为/运动策略; 数值配置统一在 props
    local runtime = {
        movement = movement,
        targetFilter = params.targetFilter,
        dedupe = params.dedupe or "entity", -- 可选策略: 缺省 entity
        onHit = onHit,
        onIntervalThink = onIntervalThink,
        onDestroy = params.onDestroy,
        selectTarget = params.selectTarget,
    }

    local cell = assert(source.cell, "projectileManager.Create: Source must be bound to a cell")
    return cell:spawnProjectile("Projectile", {
        props = {
            x = params.x or state.x,
            y = params.y or state.y,
            ownerId = state.ownerId,
            targetId = params.targetId or state.targetId,
            dir = params.dir or 0,
            speed = params.speed or 10,
            hitRadius = params.hitRadius or 2,
            areaRadius = params.areaRadius,
            tickInterval = params.tickInterval,
            duration = params.duration,
            range = params.range,
        },
        ability = ability,
        runtime = runtime,
    })
end

-- 直线投掷物(高辨识度封装, 内部走 Create)
function M.CreateLinearProjectile(params)
    return M.Create({
        Source = params.Source,
        Ability = params.Ability,
        x = params.Source.x,
        y = params.Source.y,
        movement = "linear",
        dir = params.dir or 0,
        speed = params.iMoveSpeed,
        range = params.range,
        hitRadius = params.hitRadius,
        damage = params.damage,
        onHit = params.onHit,
        onIntervalThink = params.onIntervalThink,
        onDestroy = params.onDestroy,
        selectTarget = params.selectTarget,
    })
end

-- 追踪/锁定型投掷物(高辨识度封装, 内部走 Create)
function M.CreateTrackingProjectile(params)
    return M.Create({
        Source = params.Source,
        Target = params.Target,
        Ability = params.Ability,
        x = params.Source.x,
        y = params.Source.y,
        movement = "homing",
        speed = params.iMoveSpeed,
        range = params.range,
        hitRadius = params.hitRadius,
        duration = params.duration,
        damage = params.damage,
        onHit = params.onHit,
        onIntervalThink = params.onIntervalThink,
        onDestroy = params.onDestroy,
        selectTarget = params.selectTarget,
    })
end

return M
