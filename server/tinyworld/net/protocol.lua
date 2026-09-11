-- tinyworld/net/protocol.lua
-- 具体协议构造: 统一构建对象/prop/record/view/AUTH/ACCOUNT/RPC 等消息信封。
-- 底层编码与 message.log 格式化仍由 core.proto / net.msg 负责。

local M = {}

-- ---------- 通用信封 ----------

function M.make(msgType, name, data)
    return { t = msgType, n = name, d = data or {} }
end

-- 批量信封: 把同一 tick 发给同一玩家的多条消息合并成一份, 减少跨服务发送与编码。
-- 客户端收到后按顺序展开逐条处理。msgs 为已构造好的消息表数组。
function M.batch(msgs)
    return { t = "batch", n = "msgs", d = { msgs = msgs } }
end

function M.account(name, data)
    return M.make("ACCOUNT", name, data)
end

function M.authOk(accountId, connId)
    return M.make("AUTH", "auth_ok", {
        code = 0, accountId = accountId, connId = connId, msg = "auth ok" })
end

function M.authFail(code, msg)
    return M.make("AUTH", "auth_fail", { code = code or 1, msg = msg or "bad token" })
end

function M.rpc(name, data)
    return M.make("RPC", name, data)
end

-- ---------- 对象 object ----------

-- 客户端对象快照
function M.clientProps(entity)
    local out = {}
    local schema = entity.def.propSchema
    for _, f in ipairs(schema.fields) do
        if f.sync ~= "none" and entity.props:get(f.name) ~= nil then
            out[f.name] = entity.props:get(f.name)
        end
    end
    return out
end

function M.objectAddMsg(entity)
    return { t = "object", n = "add", d = {
        entityId = entity:getRealId(), kind = entity.kind, props = M.clientProps(entity) } }
end

function M.objectRemoveMsg(entity)
    return { t = "object", n = "remove", d = { entityId = entity:getRealId() } }
end

-- object add(带 isSelf 标记, baseapp 发送给 owner)
function M.objectAddSelf(entity, props)
    return { t = "object", n = "add", d = {
        entityId = entity.cellEntityId or entity.id, kind = entity.kind,
        props = props, isSelf = true } }
end

-- spawn 之后回给 baseapp 的初始快照
function M.entitySpawnInfo(entity)
    return {
        entityId = entity:getRealId(),
        kind = entity.kind,
        props = M.clientProps(entity),
    }
end

-- ---------- 属性 prop ----------

function M.propMsg(entity, props)
    local data = { t = "prop", n = "props", d = { entityId = entity:getRealId() } }
    for k, v in pairs(props or {}) do data.d[k] = v end
    return data
end

-- ---------- 表格 record ----------

function M.recordMsg(entityId, name, ops)
    return { t = "record", n = name, d = { entityId = entityId, ops = ops } }
end

-- ---------- 视图 view ----------

function M.viewMsg(entityId, name, ops)
    return { t = "view", n = name, d = { entityId = entityId, ops = ops } }
end

return M
