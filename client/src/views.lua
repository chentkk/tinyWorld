-- client/src/views.lua
-- 通用容器(视图)客户端: 处理 add / remove / set / view op。

local M = {}

M.views = {} -- entityId -> { name -> { props, children } }

M.onChange = nil -- function(entityId, viewName, op)

function M.apply(msg)
    local entityId = msg.d and msg.d.entityId
    if not entityId then return end

    local name = msg.n
    local d = msg.d or {}
    for _, op in ipairs(d.ops or {}) do
        local byName = M.views[entityId]
        if not byName then
            byName = {}
            M.views[entityId] = byName
        end

        local view = byName[name]
        if not view then
            view = { props = {}, children = {} }
            byName[name] = view
        end

        if op.type == "add" then
            view.children[op.id] = op.data
        elseif op.type == "remove" then
            view.children[op.id] = nil
        elseif op.type == "set" then
            local child = view.children[op.id]
            if child then
                for k, v in pairs(op.data or {}) do child[k] = v end
            end
        elseif op.type == "view" then
            for k, v in pairs(op.data or {}) do view.props[k] = v end
        end

        if M.onChange then M.onChange(entityId, name, op) end
    end
end

function M.get(entityId, viewName)
    local byName = M.views[entityId]
    return byName and byName[viewName]
end

function M.clear(entityId, viewName)
    local byName = M.views[entityId]
    if byName then byName[viewName] = nil end
end

return M
