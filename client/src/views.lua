-- client/src/views.lua
-- 通用容器(视图)客户端: 处理 add / remove / set / view op。

local M = {}

M.views = {} -- name -> { id -> childData, props }

M.onChange = nil -- function(viewName, op)

function M.apply(msg)
    local name = msg.n
    local d = msg.d or {}
    for _, op in ipairs(d.ops or {}) do
        local view = M.views[name]
        if not view then
            view = { props = {}, children = {} }
            M.views[name] = view
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

        if M.onChange then M.onChange(name, op) end
    end
end

function M.get(viewName)
    return M.views[viewName]
end

function M.clear(viewName)
    M.views[viewName] = nil
end

return M
