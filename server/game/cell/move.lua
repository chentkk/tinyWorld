-- game/components/move.lua
-- 移动组件(cellapp 侧)。响应客户端与服务器其他系统的移动请求,
-- 服务器按自身速度校验后在 tick 内处理全部移动指令,
-- 最后把 coordinate+最后 sequenceid 一起下发, 客户端据此 Reconciliation。

local component = require "tinyworld.entity.component"
local direction = require "tinyworld.core.direction"
local math = math

local Move = component.extend("Move")

function Move:ctor(entity, name)
    component.ctor(self, entity, name)
    self.queue = {}
end

function Move:onCreate()
    self:registerClientRpc("onRequestMove")
    self:registerClientRpc("onStopMove")
    self:registerBaseRpc("onRequestMove") -- 服务器系统(如 ai)也可调用
end

function Move:onRequestMove(d)
    d = d or {}
    if not d.seq then return { code = 1, msg = "need seq" } end

    local dt = math.min(tonumber(d.dt) or 0, 0.2)
    self.queue[#self.queue + 1] = {
        seq = d.seq,
        dt = dt,
        dx = tonumber(d.dirX) or 0,
        dy = tonumber(d.dirY) or 0,
    }
    return nil
end

function Move:onStopMove(d)
    self.queue = {}
end

function Move:onTick(dt)
    local entity = self.entity
    if #self.queue == 0 then return end

    local speed = entity:get("speed") or 150
    local x = entity.x
    local y = entity.y
    local lastSeq
    local facing

    for _, cmd in ipairs(self.queue) do
        local dirx, diry = cmd.dx, cmd.dy
        local len = math.sqrt(dirx * dirx + diry * diry)
        if len > 0.001 then
            dirx = dirx / len
            diry = diry / len
            -- 朝向: 连续角度, 取最后一次有效移动方向(客户端再量化为 4 方向美术)
            facing = direction.angleFromVector(cmd.dx, cmd.dy)
        end
        x = x + dirx * speed * cmd.dt
        y = y + diry * speed * cmd.dt
        lastSeq = cmd.seq
    end

    self.queue = {}
    entity:set("x", x)
    entity:set("y", y)
    -- 移动确认序号作为自身属性下发(sync=self 只发给自己), 供客户端 Reconciliation
    if lastSeq then entity:set("seq", lastSeq) end
    if facing then entity:set("dir", facing) end
end

return Move
