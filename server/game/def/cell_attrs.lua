-- game/def/cell_attrs.lua
-- cell 侧需要同步的属性(include 基础属性后再补坐标等)。

return {
    props = {
        { name = "x", type = "number", sync = "all", persist = true, comment = "x 坐标", default = 10 },
        { name = "y", type = "number", sync = "all", persist = true, comment = "y 坐标", default = 10 },
        { name = "dir", type = "number", sync = "all", comment = "朝向", default = 0 },
    },
}
