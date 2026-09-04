-- tinyworld/app/baseapp.lua
-- baseapp 服务: 处理玩家自身相关逻辑(背包、装备、任务等)。
-- 登录后创建 baseentity, 从 db 加载数据; 进入世界时通过 world 选择 cell
-- 并在 cellapp 创建 real entity。baseentity 与 cellentity 支持双向 rpc。

local skynet = require "skynet"
local service = require "tinyworld.core.service"
local log = require "tinyworld.core.log"
local proto = require "tinyworld.core.proto"
local msgUtil = require "tinyworld.net.msg"
local defs = require "tinyworld.entity.defs"
local BaseEntity = require "tinyworld.app.baseapp.baseentity"
local PlayerStore = require "tinyworld.app.baseapp.player_store"

local cmd = {}
local sessions = {} -- connId -> session
local playerStore = nil
local registry
local dbmgrAddr
local worldAddr

local function dbQuery(sql)
    return skynet.call(dbmgrAddr, "lua", "query", sql)
end

local function dbExec(sql)
    return skynet.call(dbmgrAddr, "lua", "exec", sql)
end

local function dbQuote(str)
    return skynet.call(dbmgrAddr, "lua", "quote", str)
end

local function sendToClient(session, msg)
    local body = proto.encode(msg)
    skynet.send(session.gate, "lua", "send_to_client", session.connId, body,
        msg.t, msg.n, msgUtil.logData(msg.d, msg.t, msg.n))
end

local function replyAccount(session, name, data)
    sendToClient(session, msgUtil.new("ACCOUNT", name, data))
end

-- 发送自身初始化数据: 表格全量 + 视图全量
-- 发送 baseentity 的增量 record/view 变更
local function sendOwnIncrements(entity, session)
    local myId = entity.cellEntityId or entity.id
    for name, rec in pairs(entity.records) do
        local flush = rec:flushSync()
        if flush then
            sendToClient(session, msgUtil.new("record", name, { entityId = myId, ops = flush.ops }))
        end
    end
    for name, cont in pairs(entity.containers) do
        local flush = cont:flushSync()
        if flush then
            sendToClient(session, msgUtil.new("view", name, { entityId = myId, ops = flush.ops }))
        end
    end
end

local function sendOwnState(entity, session)
    for name, rec in pairs(entity.records) do
        if rec.def.sync ~= "none" then
            local ops = {}
            for _, row in pairs(rec.rows) do
                ops[#ops + 1] = { type = "add", key = rec.def:keyOf(row), data = rec:syncData(row) }
            end
            sendToClient(session, msgUtil.new("record", name,
                { entityId = entity.cellEntityId or entity.id, ops = ops }))
        end
    end

    for name, cont in pairs(entity.containers) do
        local viewId = cont:getViewId()
        if cont:isViewOpened() then
            local ops = {}
            for _, child in pairs(cont.children) do
                ops[#ops + 1] = { type = "add", id = child.id, data = cont:childFullData(child) }
            end
            sendToClient(session, msgUtil.new("view", name,
                { entityId = entity.cellEntityId or entity.id, ops = ops }))
        end
    end
end

local function sendObjectAdd(entity, session, props)
    sendToClient(session, msgUtil.new("object", "add", {
        entityId = entity.cellEntityId or entity.id, kind = entity.kind, props = props,
        isSelf = true }))
end

-- ACCOUNT 阶段处理
local function accountCharacterList(session)
    local accountId = session.accountId
    local characters = playerStore:listCharacters(accountId)
    replyAccount(session, "characterList", { code = 0, characters = characters })
end

local function accountCreateCharacter(session, d)
    local accountId = session.accountId
    local name = d.name or ("hero" .. accountId)
    local ret = playerStore:createCharacter(accountId, name)
    if not ret then
        replyAccount(session, "createCharacter", { code = 1, msg = "create fail" })
        return
    end
    accountCharacterList(session)
end

local function enterWorld(entity, session)
    local spawnX = entity:get("x") or 10
    local spawnY = entity:get("y") or 10
    local info = skynet.call(worldAddr, "lua", "spawn_info", "main", spawnX, spawnY)
    if not info then
        replyAccount(session, "selectCharacter", { code = 1, msg = "no spawn info", playerId = entity.id })
        return
    end

    local cellData = playerStore:buildCellData(entity)
    local spawn = skynet.call(info.appAddr, "lua", "spawn_entity", info.spaceId, info.cell.id,
        "Player", { x = spawnX, y = spawnY, playerId = entity.id, initData = cellData }, skynet.self())
    if not spawn then
        replyAccount(session, "selectCharacter", { code = 2, msg = "spawn fail", playerId = entity.id })
        return
    end

    entity.cellEntityId = spawn.entityId
    entity:bindCell(info.appAddr, info.cell.id, info.spaceId)
    entity.entered = true

    sendObjectAdd(entity, session, spawn.props)
    sendOwnState(entity, session)
    replyAccount(session, "selectCharacter", { code = 0, playerId = entity.id })
end

local function accountSelectCharacter(session, d)
    local playerId = tonumber(d.playerId)
    if not playerStore:characterRow(playerId) then
        replyAccount(session, "selectCharacter", { code = 1, msg = "player not found", playerId = d.playerId })
        return
    end

    local data = playerStore:load(playerId)
    local def = defs.get("Player")
    local entity = BaseEntity.new(def, playerId, "Player", session)
    entity:load(data)
    entity.account = session.accountId
    entity:onCreate()
    session.entity = entity

    entity:setupComponents(entity.def.baseComponents)
    entity:openViews(entity.def.baseOpenViews)
    enterWorld(entity, session)
end

local function handleAccount(session, msg)
    local d = msg.d or {}
    local fn = msg.n
    if fn == "characterList" then
        accountCharacterList(session)
    elseif fn == "spaceInfo" then
        local info = skynet.call(worldAddr, "lua", "query_space", "main")
        if info then replyAccount(session, "spaceInfo", info) end
    elseif fn == "createCharacter" then
        accountCreateCharacter(session, d)
    elseif fn == "selectCharacter" then
        accountSelectCharacter(session, d)
    else
        replyAccount(session, fn, { code = 1, msg = "unknown account command" })
    end
end

local function handleRpc(session, msg)
    local entity = session.entity
    if not entity then return end

    local ok, res = entity:dispatchClientMessage(msg.n, msg.d)
    if not ok then
        -- 本地 baseentity 未注册 -> 转发给 cellentity(real)
        ok, res = entity:callCellEntity(msg.n, msg.d)
    end

    if ok then
        sendToClient(session, msgUtil.new("RPC", msg.n, res or {}))
    end
end

-- gate 在 AUTH 通过后绑定会话
function cmd.open_client(gateAddr, fd, connId, accountId)
    sessions[connId] = {
        gate = gateAddr, fd = fd, connId = connId,
        accountId = accountId, entity = nil,
    }
    log.info("session open %s accountId=%s", connId, accountId)
end

-- gate 转发的客户端原始帧
function cmd.client_data(connId, body)
    local session = sessions[connId]
    if not session then return end

    local msg = proto.decode(body)
    if not msg then return end

    if msg.t == "ACCOUNT" then
        handleAccount(session, msg)
    elseif msg.t == "RPC" then
        handleRpc(session, msg)
    end
end

-- cellapp -> 客户端(实体属性 / 表格 / 视图 / 对象增减)
function cmd.client_send(msg)
    log.debug("baseapp client_send t=%s n=%s playerId=%s", tostring(msg and msg.t),
        tostring(msg and msg.n), tostring(msg and msg.playerId))
    local session = sessions[msg and msg.connId]
    if not session then
        -- 来自 cellapp: 按 playerId 精确匹配; 找不到才按 cellEntityId(对象id) 回退。
        local playerId = msg and msg.playerId
        local objId = msg and msg.d and msg.d.entityId

        if playerId then
            for connId, s in pairs(sessions) do
                if s.entity and s.entity.id == playerId then
                    session = s
                    break
                end
            end
        end

        if not session and objId then
            for connId, s in pairs(sessions) do
                if s.entity and s.entity.cellEntityId == objId then
                    session = s
                    break
                end
            end
        end
    end
    if not session then return end
    sendToClient(session, msg)
end

-- 客户端断开: 生命周期收尾 + 打包存盘(属性/表格/容器 -> player_bin)
function cmd.client_disconnect(connId)
    local session = sessions[connId]
    if not session or not session.entity then return end

    local entity = session.entity
    local dumpData = entity:dump()

    -- 坐标以 cellentity(real) 为准
    if entity.cell and entity.cellEntityId then
        local remote = skynet.call(entity.cell.appAddr, "lua", "get_entity",
            entity.cell.spaceId, entity.cellEntityId)
        if remote and remote.props then
            dumpData.props.x = remote.props.x
            dumpData.props.y = remote.props.y
        end
    end

    pcall(function() return playerStore:save(entity.id, dumpData) end)
    entity:onDestroy()
    sessions[connId] = nil
    log.info("session closed %s playerId=%d saved", connId, entity.id)
end

-- cellapp 迁移完成后通知 baseapp 更新 real 的 cell 绑定
function cmd.rebind_cell(playerId, spaceId, cellKey, appAddr)
    for _, session in pairs(sessions) do
        local entity = session.entity
        if entity and entity.id == playerId then
            entity:bindCell(appAddr, cellKey, spaceId)
            return true
        end
    end
end

-- cellentity(real) -> baseentity 的 rpc
function cmd.call_base(playerId, name, data)
    for _, session in pairs(sessions) do
        if session.entity and session.entity.id == playerId then
            return session.entity:dispatchCellRpcFromReal(name, data)
        end
    end
end

function cmd.init(registryAddr, index, gameConfig)
    registry = registryAddr
    index = index or 1

    dbmgrAddr = skynet.call(registry, "lua", "query", "dbmgr")
    worldAddr = skynet.call(registry, "lua", "query", "world")
    assert(dbmgrAddr, "dbmgr not registered")
    assert(worldAddr, "world not registered")

    require("tinyworld.combat.env").setIsServer(true)

    assert(gameConfig, "baseapp.init: gameConfig required")
    local entityDefs = assert(gameConfig.entityDefs, "gameConfig.entityDefs required")
    local baseDefs = assert(entityDefs.base, "entityDefs.base required")
    for _, bootModule in ipairs(baseDefs.boot) do
        require(bootModule)
    end
    defs.registerList(baseDefs.defs)

    playerStore = PlayerStore.new({
        query = dbQuery,
        exec = dbExec,
        quote = dbQuote,
    }, gameConfig and gameConfig.playerStore)

    skynet.call(registry, "lua", "register", "baseapp." .. index, skynet.self())

    -- 驱动 baseentity 组件(onTick), 同步压力测试组件的表格/容器变更
    skynet.fork(function()
        while true do
            for _, session in pairs(sessions) do
                local entity = session.entity
                if entity then
                    entity:onTick(1)
                    sendOwnIncrements(entity, session)
                end
            end
            skynet.sleep(100) -- 1s
        end
    end)

    log.info("baseapp ready index=%d", index)
end

service.startService("baseapp", nil, cmd)
return cmd
