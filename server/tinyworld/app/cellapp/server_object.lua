-- tinyworld/app/cellapp/server_object.lua
-- 纯服务器对象组件(客户端不可感知):
--   * networked=false 的对象不参与 outbox / ghost / visibility;
--   * 仍参与 cell tick, 可做区域感知 / 刷新控制 / 活动宿主等逻辑。
-- 本组件只负责生命周期与区域进出检测, 具体行为全部交给使用层 runtime 回调:
--   onTick / onEnter / onExit / onDestroy

local component = require "tinyworld.entity.component"

local ServerObject = component.extend("ServerObject")

function ServerObject:ctor(entity, name)
    component.ctor(self, entity, name)

    local runtime = rawget(entity, "runtime")
    assert(runtime, "ServerObject requires runtime")
    self.runtime = runtime
    self.known = {}
end

function ServerObject:onTick(dt)
    local entity = self.entity
    local runtime = self.runtime

    -- 先推进存活时间(供内部与使用层依据使用)
    local duration = entity:get("duration")
    if duration then
        self.elapsed = (self.elapsed or 0) + dt
    end

    -- 区域进出检测(显式可选, 不需要 onEnter/onExit 的对象不 query)
    if runtime.onEnter or runtime.onExit then
        local radius = entity:get("radius")
        assert(radius, "ServerObject with onEnter/onExit requires radius")
        local cell = entity.cell
        assert(cell, "ServerObject requires cell")
        local now = {}
        for _, other in ipairs(cell.spatial:query(entity.x, entity.y, radius)) do
            if other ~= entity and other:isNetworked() then
                now[other.id] = other
            end
        end

        for id, other in pairs(now) do
            if not self.known[id] then
                self.known[id] = other
                if runtime.onEnter then
                    runtime.onEnter(entity, other)
                end
            end
        end

        for id, other in pairs(self.known) do
            if not now[id] then
                self.known[id] = nil
                if runtime.onExit then
                    runtime.onExit(entity, other)
                end
            end
        end
    end

    if runtime.onTick then
        runtime.onTick(entity, dt)
    end

    -- 生命周期到期最后处理, 保证边界 tick 先执行完区域行为与 onTick
    if duration and self.elapsed >= duration then
        entity:destroy()
    end
end

function ServerObject:onDestroy()
    local runtime = self.runtime
    if runtime and runtime.onDestroy then
        runtime.onDestroy(self.entity)
    end
end

-- 创建纯服务器对象。ref 可以是 Cell, 也可以是带 cell 的实体;
-- 参数整理与 runtime 打包集中在这里, 复用 cellapp 通用 spawn_entity 入口。
function ServerObject.Create(ref, params)
    assert(params, "ServerObject.Create: params required")

    local cell = ref
    if not (cell and cell.host and cell.host.spawn_entity) then
        cell = ref and ref.cell
    end
    assert(cell and cell.host and cell.host.spawn_entity,
        "ServerObject.Create: cell required")

    local data = {
        props = {
            x = params.x or cell.info.x + cell.info.w / 2,
            y = params.y or cell.info.y + cell.info.h / 2,
            radius = params.radius,
            duration = params.duration,
        },
        runtime = {
            onTick = params.onTick,
            onEnter = params.onEnter,
            onExit = params.onExit,
            onDestroy = params.onDestroy,
        },
    }

    return cell:spawnEntity("ServerObject", data, nil)
end

return ServerObject
