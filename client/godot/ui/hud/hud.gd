# hud.gd — 抬头显示: 连接状态、日志、以及各数据面板的容器。
# 只负责"显示", 数据由外部通过 refresh() / log() 灌入。
extends CanvasLayer
class_name Hud

const PANEL_WIDTH := 420.0
const PANEL_HEIGHT := 620.0
const MAX_LOG_LINES := 16

var status_label: Label
var log_label: Label

# 可选: 由 main 注入, 返回自己当前渲染位置(Vector2)。用于让面板坐标与画面一致。
var position_provider: Callable = Callable()

# 实时坐标标签: **每帧**更新(不依赖世界状态变化), 便于观察移动与"回拉"。
# 与 _player_panel 里的坐标区别: 那个跟随世界状态刷新(低频), 这个每帧刷新。
var _pos_label: Label

var _player_panel: PlayerPanel
var _bag_panel: BagPanel
var _equip_panel: EquipmentPanel
var _task_panel: TaskPanel
var _ability_panel: AbilityPanel
var _modifier_panel: ModifierPanel

var _log_lines: Array = []


func _ready() -> void:
	_build()


func _build() -> void:
	var panel := Panel.new()
	panel.position = Vector2(8, 8)
	panel.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	panel.modulate = Color(0, 0, 0, 0.55)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(16, 16)
	vb.add_theme_constant_override("separation", 2)
	add_child(vb)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color.WHITE)
	vb.add_child(status_label)

	log_label = Label.new()
	log_label.custom_minimum_size = Vector2(PANEL_WIDTH - 20, 140)
	log_label.add_theme_font_size_override("font_size", 11)
	log_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5))
	vb.add_child(log_label)

	# 实时坐标(每帧刷新): 直接观察位置变化与服务器校正。
	_pos_label = Label.new()
	_pos_label.add_theme_font_size_override("font_size", 13)
	_pos_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	vb.add_child(_pos_label)

	_player_panel = PlayerPanel.new()
	if position_provider.is_valid():
		_player_panel.position_provider = position_provider
	vb.add_child(_player_panel)
	_bag_panel = BagPanel.new()
	vb.add_child(_bag_panel)
	_equip_panel = EquipmentPanel.new()
	vb.add_child(_equip_panel)
	_task_panel = TaskPanel.new()
	vb.add_child(_task_panel)
	_ability_panel = AbilityPanel.new()
	vb.add_child(_ability_panel)
	_modifier_panel = ModifierPanel.new()
	vb.add_child(_modifier_panel)

	var hint := Label.new()
	hint.position = Vector2(16, 740)
	hint.text = "WASD/方向键 移动 | 1-8 施法 | 左键 对准星目标施法 | 滚轮 调准星距离 | T 接任务 | R 重连"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	add_child(hint)


func set_status(text: String) -> void:
	status_label.text = text


func log(text: String) -> void:
	print("[tinyWorld] " + text)
	_log_lines.append(text)
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines = _log_lines.slice(_log_lines.size() - MAX_LOG_LINES)
	log_label.text = "\n".join(_log_lines)


# 世界状态变化后刷新所有面板。
# 每帧更新实时坐标。由 main 在主循环里调用。
# 显示: 渲染位置、距上次的位移, 以及最近一次服务器校正(负值=被往回拉)。
func update_position(render_pos: Vector2, last_delta: Vector2, last_correction: Vector2) -> void:
	var s := "位置 (%.1f, %.1f)  帧位移 (%+.2f, %+.2f)" % [
		render_pos.x, render_pos.y, last_delta.x, last_delta.y]
	# 校正量: 非零时用醒目颜色标出, 便于一眼看到"被拉"
	if last_correction.length() > 0.01:
		s += "  校正 (%+.2f, %+.2f)" % [last_correction.x, last_correction.y]
		_pos_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
	else:
		_pos_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_pos_label.text = s


func refresh(world: WorldState) -> void:
	var id := world.self_id
	_player_panel.refresh(world, id)
	_bag_panel.refresh(world, id)
	_equip_panel.refresh(world, id)
	_task_panel.refresh(world, id)
	_ability_panel.refresh(world, id)
	_modifier_panel.refresh(world, id)
