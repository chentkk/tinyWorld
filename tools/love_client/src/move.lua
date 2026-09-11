-- client/src/move.lua
-- 移动预测与 Reconciliation:
-- 本地模拟指令并缓存, 收到服务器 position+seq 后丢弃已完成指令,
-- 重放之后的指令, 避免拉扯。其他角色用最近 2 个位置更新 lerp。

local net = require "src.net"
local M = {}

M.speed = 6
M.myId = nil
M.pending = {} -- 本地缓存指令 { seq, dx, dy, dt }
M.serverSeq = 0
M.lerpA = {}
M.lerpB = {}

function M.push(entity, dx, dy, dt)
    if not entity then return end

    entity.lastSeq = (entity.lastSeq or 0) + 1
    local cmd = { seq = entity.lastSeq, dx = dx, dy = dy, dt = dt }
    M.pending[#M.pending + 1] = cmd
    net.enqueue("RPC", "onRequestMove", {
        seq = cmd.seq, dt = dt, dirX = dx, dirY = dy })

    entity.props.x = (entity.props.x or 0) + dx * M.speed * dt
    entity.props.y = (entity.props.y or 0) + dy * M.speed * dt
end

function M.stop()
    M.pending = {}
    net.enqueue("RPC", "onStopMove", {})
end

-- 服务器回包: x/y/seq, 丢弃 seq <= serverSeq 的本地指令并重放
function M.onServerPosition(entity, x, y, seq)
    entity.props.x = x
    entity.props.y = y
    M.serverSeq = seq or M.serverSeq

    local keep = {}
    for _, cmd in ipairs(M.pending) do
        if cmd.seq > M.serverSeq then
            keep[#keep + 1] = cmd
            entity.props.x = entity.props.x + cmd.dx * M.speed * cmd.dt
            entity.props.y = entity.props.y + cmd.dy * M.speed * cmd.dt
        end
    end
    M.pending = keep
end

-- 其他角色: 缓存两个位置更新包, 每帧 lerp
function M.nudgeOther(entity, x, y)
    if not M.lerpA[entity.entityId] then
        M.lerpA[entity.entityId] = { x = entity.props.x or x, y = entity.props.y or y }
    end
    M.lerpA[entity.entityId] = M.lerpB[entity.entityId] or M.lerpA[entity.entityId]
    M.lerpB[entity.entityId] = { x = x, y = y }
end

function M.updateOther(dt)
    for id, b in pairs(M.lerpB) do
        local a = M.lerpA[id]
        if a then
            a.x = a.x + (b.x - a.x) * math.min(1, dt * 8)
            a.y = a.y + (b.y - a.y) * math.min(1, dt * 8)
        end
    end
end

function M.renderPos(entity)
    local p = M.lerpA[entity.entityId]
    if p then return p.x, p.y end
    return entity.props.x, entity.props.y
end

return M
