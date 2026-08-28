-- game/def/container/modifiers_view_def.lua
-- modifiers_view 容器定义: 引用 modifier 子对象定义。

local modifierDef = require "game.def.modifier.modifier_def"

return {
    name = "modifiers_view",
    persist = false,
    viewProps = {},
    childDef = modifierDef,
}
