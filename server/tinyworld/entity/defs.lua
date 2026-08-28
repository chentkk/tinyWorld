-- tinyworld/entity/defs.lua
-- 对象定义注册表。game 启动时按 kind 注册 *_def 文件,
-- cellapp / baseapp 通过 kind 取得编译后的定义。

local compileDef = require "tinyworld.entity.entity_def"
local M = {}

M.registry = {}

function M.register(kind, defModuleOrTable)
    local def = compileDef(defModuleOrTable)
    M.registry[kind] = def
    return def
end

function M.get(kind)
    return M.registry[kind]
end

-- 按配置清单批量注册: list = { {kind="Player", module="game.def.player.player_def"}, ... }
function M.registerList(list)
    for _, item in ipairs(list or {}) do
        assert(item.kind, "def list item missing kind")
        M.register(item.kind, item.module)
    end
end

function M.each(fn)
    for kind, def in pairs(M.registry) do
        fn(kind, def)
    end
end

return M
