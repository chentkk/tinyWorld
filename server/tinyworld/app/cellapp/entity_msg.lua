-- tinyworld/app/cellapp/entity_msg.lua
-- 对象对外消息构造: object add/remove 与客户端属性快照。

local combatUnit = require "tinyworld.combat.unit"
local M = {}
-- 客户端对象快照
local function clientProps(entity)
    local out = {}
    local schema = entity.def.propSchema
    for _, f in ipairs(schema.fields) do
        if f.sync ~= "none" and entity.props:get(f.name) ~= nil then
            out[f.name] = entity.props:get(f.name)
        end
    end
    return out
end

M.clientProps = clientProps

-- 下发对象新增 message
function M.objectAddMsg(entity)
    return { t = "object", n = "add", d = {
        entityId = entity.clientId or entity.id, kind = entity.kind, props = clientProps(entity),
        modifiers = combatUnit.modifiersSnapshot(entity) } }
end

function M.objectRemoveMsg(entity)
    return { t = "object", n = "remove", d = { entityId = entity.clientId or entity.id } }
end

-- spawn 之后回给 baseapp 的初始快照。object add 与 spawn 共用同一份展示数据,
-- 避免在命令处理中散落实体表现逻辑。
function M.entitySpawnInfo(entity)
    return {
        entityId = entity.clientId or entity.id,
        kind = entity.kind,
        props = clientProps(entity),
        modifiers = combatUnit.modifiersSnapshot(entity),
    }
end

return M
