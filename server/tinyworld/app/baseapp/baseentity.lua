-- tinyworld/app/baseapp/baseentity.lua
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
    self._toredown = false
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

-- 退出 / 换 cell 时解除 cellentity 绑定
function BaseEntity:unbindCell()
    self.cell = nil
    self.cellEntityId = nil
    self.entered = false
end

-- 幂等收尾: 本侧实体没有 cell 运行时对象(只有绑定信息), 不能走 Entity.destroy
function BaseEntity:teardown()
    if self._toredown then return end
    self._toredown = true
    self:onDestroy()
    self:unbindCell()
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
