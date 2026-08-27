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

function M.each(fn)
    for kind, def in pairs(M.registry) do
        fn(kind, def)
    end
end

return M
