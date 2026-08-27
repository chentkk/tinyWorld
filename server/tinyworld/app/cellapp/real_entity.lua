-- tinyworld/app/cellapp/real_entity.lua
-- RealEntity(真身): cell 内的权威实体。
-- 每 tick 由 Cell 打包 outbox, 观察者领取; 同时 outbox 交给关联 ghost。

local Entity = require "tinyworld.entity.entity"
local RealEntity = Entity.extend("RealEntity")

function RealEntity:ctor(def, id, kind, space, cell, x, y)
    Entity.ctor(self, def, id, kind)
    self.clientId = id
    self.isReal = true
    self.space = space
    self.cell = cell
    self.x = x or 0
    self.y = y or 0
    self.ghosts = {} -- 维护真实对象关联的 ghost 列表
    self.moving = false
    self.lastMigrateTime = 0
    self.baseApp = nil
    self.readyForSync = false
    self.pendingEvents = {}
    self.extra = {}
end

function RealEntity:setPosition(x, y, source)
    local space = self.space
    x = math.max(space.bounds.x1, math.min(space.bounds.x2, x))
    y = math.max(space.bounds.y1, math.min(space.bounds.y2, y))
    self.x = x
    self.y = y
end

function RealEntity:setBaseApp(addr)
    self.baseApp = addr
end

-- 属性变化: 记录 ghost 同步候选 + 客户端广播候选
function RealEntity:onPropChanged(name, value, mode, source)
    if mode ~= "none" then
        self.dirtyClient[name] = value
    end
end

-- override 基类钩子
function RealEntity:onPropChange(name, value, mode, source)
    if name == "x" or name == "y" then
        rawset(self, name, value)
    end
    self:onPropChanged(name, value, mode, source)
    self:emit("prop_change", name, value, mode, source)
    self:eachComponent(function(_, comp)
        if comp.onPropChange then comp:onPropChange(name, value, mode, source) end
    end)
end

function RealEntity:addGhost(ghostInfo)
    self.ghosts[ghostInfo.key] = ghostInfo
end

function RealEntity:removeGhost(key)
    self.ghosts[key] = nil
end

function RealEntity:ghostSnapshot()
    return { props = self.props:dump(), records = self:dump().records, containers = self:dump().containers }
end

function RealEntity:applySnapshot(snap)
    if snap.props then self.props:load(snap.props) end
end

function RealEntity:onDestroy()
    Entity.onDestroy(self)
end

return RealEntity
