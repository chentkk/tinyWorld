-- client/main.lua
-- love2d 客户端入口: 连接服务器 -> 登录 -> 选择角色进入世界。
-- 本地 entity 接收同步、WASD 移动(本地模拟 + Reconciliation)、
-- 绘制 cell / ghost 边界, 展示通用视图(背包、装备栏)界面。

local net = require "src.net"
local dbg = require "src.debuglog"
local entities = require "src.entities"
local views = require "src.views"
local records = require "src.records"
local move = require "src.move"
local ui = require "src.ui"

local HOST = "127.0.0.1"
local LOGIN_PORT = 8080
local GAME_PORT = 8000

-- 命令行: love 游戏目录 账号 [自动退出秒数] [automove]
local account = (arg and arg[2]) or "test1"
local autoQuitAfter = tonumber(arg and arg[3])
local autoMove = (arg and arg[4] == "automove") or false
local autoCast = (arg and arg[5] == "cast") or false
local didCast = false
local testTimer = 0

local state = "login" -- login / select / enter / world
local combatEvents = {}
local spaceInfo = nil
local myEntity = nil
local keys = { left = false, right = false, up = false, down = false }

local function sendSelect(playerId)
    net.enqueue("ACCOUNT", "selectCharacter", { playerId = playerId })
end

local function requestSpaceInfo()
    net.enqueue("ACCOUNT", "spaceInfo", {})
end

net.onMessage = function(msg)
    local d = msg.d or {}
    if msg.t == "AUTH" or msg.t == "ACCOUNT" then
        dbg.write("recv %s %s", msg.t, msg.n)
    end

    if msg.t == "AUTH" and msg.n == "auth_ok" then
        state = "select"
        net.enqueue("ACCOUNT", "characterList", {})
    elseif msg.t == "ACCOUNT" and msg.n == "characterList" then
        local chars = d.characters or {}
        if chars[1] then
            sendSelect(chars[1].id)
            state = "enter"
        end
    elseif msg.t == "ACCOUNT" and msg.n == "spaceInfo" then
        spaceInfo = d
    elseif msg.t == "object" then
        entities.apply(msg)
        dbg.write("recv object add entity=%s isSelf=%s", tostring(d.entityId), tostring(d.isSelf))
        if msg.n == "add" and d.isSelf then
            net.selfId = d.entityId
            local e = entities.get(d.entityId)
            myEntity = e
            move.myId = d.entityId
            state = "world"
            requestSpaceInfo()
        end
    elseif msg.t == "prop" then
        local e = entities.applyProp(msg)
        if e then
            if e.entityId == net.selfId and myEntity then
                move.onServerPosition(myEntity, d.x, d.y, d.seq)
            elseif e.entityId ~= net.selfId then
                move.nudgeOther(e, d.x, d.y)
            end
        end
    elseif msg.t == "record" then
        records.apply(msg)
    elseif msg.t == "view" then
        views.apply(msg)
    elseif msg.t == "RPC" then
        -- 服务器主动推送的战斗事件: 伤害 / 治疗 / modifier 变化
        local e = entities.get(d.entityId)
        local x, y = e and e.props.x, e and e.props.y
        if msg.n == "onCombatDamage" then
            combatEvents[#combatEvents + 1] = { text = "-" .. d.amount, x = x, y = y, ttl = 1 }
        elseif msg.n == "onCombatHeal" then
            combatEvents[#combatEvents + 1] = { text = "+" .. d.amount, x = x, y = y, ttl = 1 }
        elseif msg.n == "onModifierAdd" then
            combatEvents[#combatEvents + 1] = { text = "+" .. (d.modifier or ""), x = x, y = y, ttl = 1.2 }
        elseif msg.n == "onModifierRemove" then
            combatEvents[#combatEvents + 1] = { text = "-" .. (d.modifier or ""), x = x, y = y, ttl = 1.2 }
        end
    end
end

function love.load()
    love.graphics.setBackgroundColor(0.1, 0.1, 0.14)
    dbg.write("client start account=%s autoMove=%s autoCast=%s autoQuit=%s", account, tostring(autoMove), tostring(autoCast), tostring(autoQuitAfter))

    local token = net.login(HOST, LOGIN_PORT, account, "123456")
    dbg.write("login token=%s", tostring(token and token.token))
    if not token or token.code ~= 0 then
        state = "error"
        return
    end

    local ok, err = net.connect(HOST, GAME_PORT)
    dbg.write("connect ok=%s err=%s", tostring(ok), tostring(err))
    if not ok then
        state = "error"
        return
    end

    net.enqueue("AUTH", "auth", { token = token.token })
    dbg.write("auth enqueued")
end

local function inputDirection()
    local dx, dy = 0, 0
    if keys.left then dx = -1 end
    if keys.right then dx = dx + 1 end
    if keys.up then dy = -1 end
    if keys.down then dy = dy + 1 end
    return dx, dy
end

local function moving()
    return keys.left or keys.right or keys.up or keys.down
end

function love.update(dt)
    net.update()

    if state == "world" and myEntity then
        move.updateOther(dt)
        local dx, dy = inputDirection()
        if autoMove and (dx == 0 and dy == 0) then
            dx, dy = 1, 0 -- 测试模式: 持续向右移动, 验证 Reconciliation 与周围同步
        end
        if dx ~= 0 or dy ~= 0 then
            local inv = 1 / math.sqrt(dx * dx + dy * dy)
            move.push(myEntity, dx * inv, dy * inv, dt)
        elseif #move.pending > 0 then
            move.stop()
        end
    end

    -- 战斗飘字凋亡
    for i = #combatEvents, 1, -1 do
        combatEvents[i].ttl = combatEvents[i].ttl - dt
        if combatEvents[i].ttl <= 0 then table.remove(combatEvents, i) end
    end

    if autoCast and state == "world" and myEntity and not didCast then
        didCast = true
        net.enqueue("RPC", "onCastAbility", { index = 3 })
        dbg.write("cast ability index=3")
    end

    if autoQuitAfter then
        testTimer = testTimer + dt
        if testTimer >= autoQuitAfter then
            dbg.write("auto quit after %ds", autoQuitAfter)
            os.exit(0)
        end
    end
end

local function drawCell(cell, mode)
    local x, y, w, h = cell.x, cell.y, cell.w, cell.h
    if mode == "normal" then
        love.graphics.setColor(0.2, 0.8, 0.2, 0.6)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x, y, w, h)
    else
        love.graphics.setColor(1, 0.9, 0.2, 0.7)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, w, h)
        love.graphics.setColor(0.3, 0.6, 1.0, 0.5)
        love.graphics.rectangle("line", x - 2, y - 2, w + 4, h + 4)
    end
end

local function cellIndex(x, y, size)
    return math.floor(x / size), math.floor(y / size)
end

function love.draw()
    if state == "error" then
        love.graphics.print("connect/login failed", 20, 20)
        return
    end

    if spaceInfo and ui.showGrid then
        local size = spaceInfo.cellSize or 100
        for _, cell in ipairs(spaceInfo.cells or {}) do
            drawCell(cell, "normal")
        end

        if myEntity and myEntity.props.x then
            local cx, cy = cellIndex(myEntity.props.x, myEntity.props.y, size)
            local cols, rows = math.floor((spaceInfo.width or 200) / size), math.floor((spaceInfo.height or 200) / size)
            for dy = -1, 1 do
                for dx = -1, 1 do
                    if dx ~= 0 or dy ~= 0 then
                        local nx, ny = cx + dx, cy + dy
                        if nx >= 0 and nx < cols and ny >= 0 and ny < rows then
                            drawCell({ x = nx * size, y = ny * size, w = size, h = size }, "ghost")
                        end
                    end
                end
            end

            -- 自己 cell 高亮
            drawCell({ x = cx * size, y = cy * size, w = size, h = size }, "ghost")
        end
    end

    -- 实体绘制
    for _, e in pairs(entities.list) do
        local x, y = e.props.x, e.props.y
        if e.entityId ~= net.selfId then
            x, y = move.renderPos(e)
        end
        if x then
            love.graphics.setColor(e.entityId == net.selfId and 1 or 1, e.entityId == net.selfId and 0.3 or 0.8, 0.3)
            love.graphics.circle("fill", x, y, e.entityId == net.selfId and 6 or 5)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print((e.props.name or "") .. " L" .. (e.props.level or 0), x - 14, y - 18)
        end
    end

    -- 任务表格(当前任务)
    local cur = records.get("current_tasks")
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("tasks: " .. tostring(0), 10, 120)
    local i = 0
    for _, row in pairs(cur) do
        love.graphics.print("task " .. tostring(row.taskid) .. " p" .. tostring(row.progress), 10, 140 + i * 16)
        i = i + 1
    end

    -- 战斗事件飘字(伤害数字 / modifier 提示)
    for _, ev in ipairs(combatEvents) do
        if ev.x and ev.y then
            love.graphics.setColor(1, ev.text:sub(1,1) == "-" and 0.9 or 0.3, 0.3)
            love.graphics.print(ev.text, ev.x, ev.y - 24)
        end
    end

    ui.draw()
end

function love.keypressed(key)
    if key == "a" then keys.left = true
    elseif key == "d" then keys.right = true
    elseif key == "w" then keys.up = true
    elseif key == "s" then keys.down = true end
end

function love.keyreleased(key)
    if key == "a" then keys.left = false
    elseif key == "d" then keys.right = false
    elseif key == "w" then keys.up = false
    elseif key == "s" then keys.down = false end
end

function love.mousepressed(x, y, button)
    if button == 1 then ui.mousepressed(x, y) end
end
