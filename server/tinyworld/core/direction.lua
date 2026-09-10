-- tinyworld/core/direction.lua
-- 朝向工具。实体朝向(属性 dir)存连续角度(弧度), 支持任意方向自由移动;
-- "4 方向"只是客户端美术表现, 由本模块把连续角度量化为 4 个方向之一。
--
-- 角度约定(与 math.cos/sin 一致): 0 = 右, pi/2 = 下, pi = 左, -pi/2 = 上。
-- 世界坐标: x 向右为正, y 向下为正(与客户端屏幕坐标一致)。

local M = {}

-- 4 方向枚举(客户端美术用)
M.DOWN = 0
M.LEFT = 1
M.UP = 2
M.RIGHT = 3

M.pi2 = math.pi * 2

-- 量化时的遍历顺序, 决定正好落在 45 度分界线上的取整结果(取靠前者):
-- 45度 -> RIGHT, 135度 -> DOWN, 225度 -> LEFT, 315度 -> UP
local DIRECTIONS = { M.RIGHT, M.DOWN, M.LEFT, M.UP }

-- 方向中心角度(弧度)
local ANGLES = {
    [M.RIGHT] = 0,
    [M.DOWN]  = math.pi / 2,
    [M.LEFT]  = math.pi,
    [M.UP]    = -math.pi / 2,
}

function M.angle(dir)
    return ANGLES[dir]
end

function M.isValid(dir)
    return ANGLES[dir] ~= nil
end

-- 把任意角度归一化到 [-pi, pi)
function M.normalize(angle)
    angle = angle % M.pi2
    if angle >= math.pi then angle = angle - M.pi2 end
    return angle
end

-- 角度差(取最短, 结果在 [-pi, pi))
function M.delta(a, b)
    return M.normalize(a - b)
end

-- 由移动向量求连续角度; 零向量返回 nil(不改变朝向)
function M.angleFromVector(dx, dy)
    if dx == 0 and dy == 0 then return nil end
    return math.atan(dy, dx)
end

-- 把连续角度量化为 4 方向之一(客户端选美术用)
function M.quantize(angle)
    angle = M.normalize(angle)
    -- 距离各方向中心角度, 取最近
    local best, bestDiff
    for _, dir in ipairs(DIRECTIONS) do
        local diff = math.abs(M.delta(angle, ANGLES[dir]))
        if not bestDiff or diff < bestDiff then
            best, bestDiff = dir, diff
        end
    end
    return best
end

return M
