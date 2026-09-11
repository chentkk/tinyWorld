# map_view.gd — 地图的加载 / 卸载生命周期。
#
# 为什么需要独立的地图概念:
#   当前只有一个常驻的无限网格, 没有"地图"这个实体。后续要支持多张地图
#   (main / dungeon_1001 ...), 就必须有明确的加载/卸载入口, 否则资源会越积越多、
#   切图时状态残留。
#
# 生命周期:
#   load_map(info)   进入某地图: 记下几何, 建立网格, 打开地图资源
#   unload_map()     离开地图:   释放资源、清空网格
#   切换地图 = unload -> load(由调用方按序执行, 保证不残留)
#
# 几何来源: 服务端 ACCOUNT spaceInfo(width/height/cellSize/cells)。
extends Node2D
class_name MapView

const WorldGrid := preload("res://ui/world/world_grid.gd")

signal map_loaded(map_id: String)
signal map_unloaded(map_id: String)

const DEFAULT_CELL_SIZE := 500.0

# 当前地图 id; 空表示未加载。
var map_id: String = ""
var width := 0.0
var height := 0.0
var cell_size := DEFAULT_CELL_SIZE

var _grid: WorldGrid


func is_loaded() -> bool:
	return not map_id.is_empty()


func _ready() -> void:
	_grid = WorldGrid.new()
	_grid.name = "Grid"
	add_child(_grid)


# 进入地图。重复加载同一张地图时先卸载, 保证干净状态。
func load_map(space: Dictionary) -> void:
	var new_id := str(space.get("id", ""))
	if is_loaded():
		unload_map()

	map_id = new_id
	width = float(space.get("width", 0.0))
	height = float(space.get("height", 0.0))
	cell_size = float(space.get("cellSize", DEFAULT_CELL_SIZE))
	if cell_size <= 0.0:
		cell_size = DEFAULT_CELL_SIZE

	_grid.set_world_size(width, height)
	_grid.cell_size = cell_size
	_grid.visible = true
	_grid.queue_redraw()

	map_loaded.emit(map_id)


# 离开地图: 释放该地图的资源, 清空网格。
func unload_map() -> void:
	if not is_loaded():
		return
	var old_id := map_id
	map_id = ""
	width = 0.0
	height = 0.0

	_grid.set_world_size(0.0, 0.0)
	_grid.visible = false
	_grid.queue_redraw()

	map_unloaded.emit(old_id)


# 高亮当前所在格(网格内部只在跨格时重绘)。
func set_focus(world_pos: Vector2) -> void:
	if is_loaded():
		_grid.set_focus(world_pos)


# 世界尺寸是否已知(用于网格标注)。
func has_bounds() -> bool:
	return width > 0.0 and height > 0.0
