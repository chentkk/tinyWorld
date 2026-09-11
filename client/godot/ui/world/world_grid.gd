# world_grid.gd — 世界网格背景, 为移动与定位提供视觉参照。
#
# 摄像机始终跟随玩家, 玩家固定在屏幕偏左处。因此"我在哪 / 我有没有在动"完全
# 依赖背景的可读性 —— 网格太淡会误判为"角色没动", 标注太稀又读不出坐标。
#
# 网格**跟随摄像机无限铺开**(而非只画 space 的 0~2000 范围):
#   服务端 Move:onTick 绕过了边界 clamp, 玩家可能跑到 space 之外(实测 x=17000+)。
#   若网格只在 0~2000 内绘制, 出界后就是一片纯黑, 完全失去移动参照。
#   真实世界范围另用醒目边框标出, 不会与"无限网格"混淆。
#
# 分层(由弱到强):
#   * 棋盘格底色   —— 移动的连续视觉线索
#   * 次刻度线     —— 近距离参照
#   * 主刻度线     —— 每 500 一格, 与服务器 cellSize 对齐
#   * 世界边界框   —— 标出 space 的真实范围(0,0)-(width,height)
#   * 刻度标注     —— 直接读出坐标
#   * 当前格高亮   —— 由 set_focus() 更新
extends Node2D

const DEFAULT_CELL_SIZE := 500.0   # 默认主格, 与服务器 cellSize 一致
# 主格尺寸。由 MapView 按 spaceInfo.cellSize 设置(不同地图可能不同)。
var cell_size := DEFAULT_CELL_SIZE
const TICK_SIZE := 100.0      # 次刻度

# 网格向四周额外铺开的格数(以当前格为中心)。9x9 足够覆盖任何视口。
const PAD_CELLS := 4

const CHECKER_A := Color(1, 1, 1, 0.030)
const CHECKER_B := Color(1, 1, 1, 0.055)

const TICK_COLOR := Color(1, 1, 1, 0.12)
const MAJOR_COLOR := Color(0.45, 0.75, 1.0, 0.40)
const AXIS_X_COLOR := Color(1.0, 0.35, 0.35, 0.80)   # y=0 轴 - 红
const AXIS_Y_COLOR := Color(0.4, 1.0, 0.4, 0.80)     # x=0 轴 - 绿
const BORDER_COLOR := Color(1, 0.6, 0.3, 0.9)        # 世界边界

const TICK_LABEL_COLOR := Color(0.7, 0.8, 0.95, 0.45)
const MAJOR_LABEL_COLOR := Color(0.85, 0.92, 1.0, 0.85)
const FOCUS_COLOR := Color(1.0, 0.9, 0.3, 0.9)
const OUTSIDE_COLOR := Color(1.0, 0.35, 0.35, 0.9)   # 世界之外的坐标标注

# 世界尺寸(来自 spaceInfo), 0 表示未知。
var _world_w := 0.0
var _world_h := 0.0
# 当前所在格, 决定网格铺开的中心。
var _focus_cell := Vector2i(0, 0)


# 设置世界尺寸(来自 spaceInfo)。传 0 表示未知/未加载, 此时不画边界框。
func set_world_size(width: float, height: float) -> void:
	_world_w = maxf(width, 0.0)
	_world_h = maxf(height, 0.0)
	queue_redraw()


# 更新"我在哪个格"; 仅在跨格时重绘(避免每帧重绘整片网格)。
func set_focus(world_pos: Vector2) -> void:
	var cell := Vector2i(floori(world_pos.x / cell_size), floori(world_pos.y / cell_size))
	if cell == _focus_cell:
		return
	_focus_cell = cell
	queue_redraw()


func _draw() -> void:
	var c0 := _focus_cell - Vector2i(PAD_CELLS, PAD_CELLS)
	var c1 := _focus_cell + Vector2i(PAD_CELLS, PAD_CELLS)

	_draw_checker(c0, c1)
	_draw_lines(c0, c1)
	_draw_world_border()
	_draw_focus()
	_draw_labels(c0, c1)


# 棋盘格底色: 移动时整片色块滑过, 是最直观的"在动"线索。
func _draw_checker(c0: Vector2i, c1: Vector2i) -> void:
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var color := CHECKER_A if (cx + cy) % 2 == 0 else CHECKER_B
			draw_rect(Rect2(cx * cell_size, cy * cell_size, cell_size, cell_size),
				color, true)


func _draw_lines(c0: Vector2i, c1: Vector2i) -> void:
	var x0 := c0.x * cell_size
	var y0 := c0.y * cell_size
	var x1 := c1.x * cell_size
	var y1 := c1.y * cell_size

	# 次刻度(100)
	var v := ceilf(x0 / TICK_SIZE) * TICK_SIZE
	while v <= x1:
		if fmod(v, cell_size) != 0.0:
			draw_line(Vector2(v, y0), Vector2(v, y1), TICK_COLOR, 1.0)
		v += TICK_SIZE
	v = ceilf(y0 / TICK_SIZE) * TICK_SIZE
	while v <= y1:
		if fmod(v, cell_size) != 0.0:
			draw_line(Vector2(x0, v), Vector2(x1, v), TICK_COLOR, 1.0)
		v += TICK_SIZE

	# 主刻度(500)
	v = c0.x * cell_size
	while v <= x1:
		draw_line(Vector2(v, y0), Vector2(v, y1), MAJOR_COLOR, 1.5)
		v += cell_size
	v = c0.y * cell_size
	while v <= y1:
		draw_line(Vector2(x0, v), Vector2(x1, v), MAJOR_COLOR, 1.5)
		v += cell_size

	# 坐标轴(x=0 / y=0), 便于绝对定位
	if x0 <= 0.0 and 0.0 <= x1:
		draw_line(Vector2(0, y0), Vector2(0, y1), AXIS_Y_COLOR, 3.0)
	if y0 <= 0.0 and 0.0 <= y1:
		draw_line(Vector2(x0, 0), Vector2(x1, 0), AXIS_X_COLOR, 3.0)


# 世界边界框(space 的真实范围)。玩家出界时这个框会滑出视野, 由此也能看出已出界。
func _draw_world_border() -> void:
	if _world_w <= 0.0 or _world_h <= 0.0:
		return
	draw_rect(Rect2(0, 0, _world_w, _world_h), BORDER_COLOR, false, 3.0)


# 高亮当前所在格。
func _draw_focus() -> void:
	var r := Rect2(_focus_cell.x * cell_size, _focus_cell.y * cell_size,
		cell_size, cell_size)
	draw_rect(r, Color(FOCUS_COLOR.r, FOCUS_COLOR.g, FOCUS_COLOR.b, 0.10), true)
	draw_rect(r, FOCUS_COLOR, false, 2.0)


func _draw_labels(c0: Vector2i, c1: Vector2i) -> void:
	var font := ThemeDB.fallback_font

	# 次刻度小字
	var v := ceilf(c0.x * cell_size / TICK_SIZE) * TICK_SIZE
	while v <= c1.x * cell_size:
		if fmod(v, cell_size) != 0.0:
			draw_string(font, Vector2(v + 3, c0.y * cell_size + 14), "%d" % int(v),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TICK_LABEL_COLOR)
		v += TICK_SIZE
	v = ceilf(c0.y * cell_size / TICK_SIZE) * TICK_SIZE
	while v <= c1.y * cell_size:
		if fmod(v, cell_size) != 0.0:
			draw_string(font, Vector2(c0.x * cell_size + 3, v + 13), "%d" % int(v),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TICK_LABEL_COLOR)
		v += TICK_SIZE

	# 主刻度大字(每个格左上角标 "x,y"); 世界之外用红色区分。
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var wx := cx * cell_size
			var wy := cy * cell_size
			var color := MAJOR_LABEL_COLOR
			if _world_w > 0.0 and (wx < 0.0 or wy < 0.0 or wx >= _world_w or wy >= _world_h):
				color = OUTSIDE_COLOR
			draw_string(font, Vector2(wx + 8, wy + 34), "%d,%d" % [int(wx), int(wy)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)
