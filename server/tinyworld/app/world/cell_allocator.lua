-- tinyworld/app/world/cell_allocator.lua
-- cellapp 运行时分配策略(纯函数)。world 持有本模块并在创建 space 时调用。
-- SpaceConfig 只负责切分 space, 不负责任何 cellapp 归属。

local M = {}

-- 当前策略: 按 appIds 顺序轮询, 把 space.cells 均匀分给各 cellapp。
-- 后续可在 world 侧接入 cellapp_report 的负载反馈, 选择更优起点。
function M.distribute(config, appIds)
    appIds = appIds or {}
    if #appIds == 0 then
        return false, "no cellapp available"
    end

    local byApp = {}
    for i, info in ipairs(config.cells) do
        local appId = appIds[((i - 1) % #appIds) + 1]
        info.appId = appId
        byApp[appId] = byApp[appId] or {}
        byApp[appId][#byApp[appId] + 1] = info
    end
    return true, byApp
end

return M
