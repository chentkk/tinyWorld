-- tinyworld/entity/baseentity.lua
-- baseapp 上的玩家实体: 加载 db 数据, 处理客户端 rpc(带登录完成 middleware),
-- 与 cellentity(real entity) 双向 rpc。

local Entity = require "tinyworld.entity.entity"

local BaseEntity = Entity.extend("BaseEntity")

function BaseEntity:ctor(def, id, kind, conn)
    Entity.ctor(self, def, id, kind or "Player")
    self.conn = conn -- { gate, fd, connId }
    self.account = conn and conn.account
    self.entered = false
    self.cell = nil -- { appAddr, cellKey }
end

-- middleware: 登录完成(rpc 前必须 enterWorld)才能调用
function BaseEntity:dispatchClientMessage(name, data)
    if not self.entered then
        return nil, "not entered world"
    end
    return self:dispatchClientRpc(name, data)
end

function BaseEntity:bindCell(appAddr, cellKey, spaceId)
    self.cell = { appAddr = appAddr, cellKey = cellKey, spaceId = spaceId }
end

-- baseapp -> cellentity(real) rpc
function BaseEntity:callCellEntity(name, data)
    local skynet = require "skynet"
    if not self.cell then return nil, "no cell" end
    return skynet.call(self.cell.appAddr, "lua", "call_cell_rpc",
        self.cell.spaceId, self.cellEntityId or self.id, self.cell.cellKey, name, data)
end

function BaseEntity:sendCellEntity(name, data)
    local skynet = require "skynet"
    if not self.cell then return end
    skynet.send(self.cell.appAddr, "lua", "call_cell_rpc",
        self.cell.spaceId, self.cellEntityId or self.id, self.cell.cellKey, name, data)
end

-- cellentity -> baseentity rpc (由 baseapp 服务转发调用)
function BaseEntity:dispatchCellRpcFromReal(name, data)
    return self:dispatchCellRpc(name, data)
end

return BaseEntity
