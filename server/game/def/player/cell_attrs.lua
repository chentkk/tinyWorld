-- game/def/player/cell_attrs.lua
-- cell 侧需要同步的属性(include 基础属性后再补坐标与朝向等)。
-- dir: 连续朝向角(弧度, 0=右 / pi/2=下)。移动为任意方向自由移动,
--      客户端按 4 方向美术把 dir 量化后选择 sprite(见 tinyworld.core.direction)。

return {
    props = {
        { name = "x", type = "number", sync = "all", persist = true, comment = "x 坐标", default = 10 },
        { name = "y", type = "number", sync = "all", persist = true, comment = "y 坐标", default = 10 },
        { name = "dir", type = "number", sync = "all", persist = true, comment = "朝向角(弧度)", default = 0 },
    },
}
