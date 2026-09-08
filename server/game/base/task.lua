-- game/components/task.lua
-- 任务组件: 使用通用表格 Record 实现。
-- current_tasks 同步客户端, completed_tasks 仅服务器内部使用。

local component = require "tinyworld.entity.component"

local Task = component.extend("Task")

function Task:onCreate()
    self:registerClientRpc("onAcceptTask")
end

function Task:onAcceptTask(d)
    local entity = self.entity
    local current = entity:getRecord("current_tasks")
    local taskid = tonumber(d.taskid)
    if not taskid then return { code = 1, msg = "bad task" } end
    if current:get(tostring(taskid)) then return { code = 2, msg = "task exists" } end

    current:add({ taskid = taskid, state = 0, progress = 0 })
    return nil
end

-- 完成任务: 移出当前列表并记录到已完成列表
function Task:complete(taskid)
    local entity = self.entity
    local current = entity:getRecord("current_tasks")
    local completed = entity:getRecord("completed_tasks")

    if not current:get(tostring(taskid)) then return false end
    current:remove(tostring(taskid))
    completed:add({ taskid = taskid })
    return true
end

return Task
