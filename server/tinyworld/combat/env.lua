-- game/scripts/vscripts/combat/env.lua
-- 战斗环境: 客户端 / 服务器共用同一份逻辑, 由 IsServer() 区分。

local M = {}

local isServer = false

function M.setIsServer(v)
    isServer = v and true or false
end

function M.IsServer()
    return isServer
end

return M
