-- client/src/entities.lua
-- 本地 entity 集合: 接受服务器 object / prop 同步。

local M = {}

M.list = {} -- clientId -> entity

M.onAddHandlers = {}
M.onRemoveHandlers = {}

local function callHook(list, entity, ...)
    for _, fn in ipairs(list) do fn(entity, ...) end
end

function M.onObjectAdd(fn) M.onAddHandlers[#M.onAddHandlers + 1] = fn end
function M.onObjectRemove(fn) M.onRemoveHandlers[#M.onRemoveHandlers + 1] = fn end

function M.apply(msg)
    local d = msg.d or {}
    if msg.n == "add" then
        local e = { entityId = d.entityId, kind = d.kind, props = d.props or {},
                    modifiers = d.modifiers or {} }
        M.list[d.entityId] = e
        callHook(M.onAddHandlers, e)
    elseif msg.n == "remove" then
        local e = M.list[d.entityId]
        if e then
            M.list[d.entityId] = nil
            callHook(M.onRemoveHandlers, e)
        end
    end
end

function M.applyProp(msg)
    local d = msg.d or {}
    local e = M.list[d.entityId]
    if not e then return end
    for k, v in pairs(d) do
        if k ~= "entityId" then e.props[k] = v end
    end
    if d.seq then e.lastSeq = d.seq end
    return e
end

function M.get(id) return M.list[id] end

return M
