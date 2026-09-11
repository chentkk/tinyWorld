# actor_node.gd — 实体的可见表现(配置驱动)。
#
# 表现差异(有无美术/是否显示名字/颜色/半径/层级)全部来自 ActorDef 配置,
# 本类不含 kind 的 if/else —— 新增 NPC/投掷物只需在 actor_defs.json 加一项。
#
# 两种模式, 由配置决定:
#   1. 序列帧模式: 配置了 sprite 且加载成功 -> AnimatedSprite2D 播放
#      "<动作>_<朝向>" 动画;
#   2. 占位模式: 无美术资源时用 _draw() 画圆点(保证无资源也能跑通全流程)。
#
# 朝向: 服务端 dir 是连续角度, 经 Direction.quantize() 量化到 4 向,
#       再由 Facing.render_for() 映射到美术行 + 是否水平翻转。
extends Node2D
class_name ActorNode

# 动画名里用到的行名候选(用于从已加载动画反推美术支持哪些朝向)。
const ROW_CANDIDATES := ["down", "up", "left", "right", "side"]

enum Action { IDLE, WALK, ATTACK }

const ACTION_NAMES := {
	Action.IDLE: "idle",
	Action.WALK: "walk",
	Action.ATTACK: "attack",
}

const COLOR_FACING := Color(1.0, 1.0, 0.3)

var entity_id: int = 0
var kind: String = ""
var is_self: bool = false

# 当前 4 向朝向(Direction 枚举)与动作。
var facing_dir: int = Direction.RIGHT
var action: int = Action.IDLE

# 本实体的表现定义(来自 ActorDef)。
var def: Dictionary = {}

var _sprite: AnimatedSprite2D
var _label: Label
var _has_art := false
# 美术实际支持的行名(从已加载动画反推)。
var _rows: Array = []
# 占位绘制的半径与颜色(来自配置)。
var _radius := 8.0
var _body_color := Color(1.0, 0.45, 0.2)
# 已向 AssetCache 申请的 sprite 路径(释放时用)。
var _sprite_path := ""


func setup(p_id: int, p_kind: String, p_self: bool) -> void:
	entity_id = p_id
	kind = p_kind
	is_self = p_self
	def = ActorDef.get_def(p_kind)

	z_index = int(def.get("z_index", 10))
	_radius = float(def.get("placeholder_radius", 8.0))
	_body_color = def.get("placeholder_color", Color(1.0, 0.45, 0.2))
	# 自己用高亮色, 便于在人群中辨认(与配置色区分)。
	if is_self:
		_body_color = Color(0.2, 0.5, 1.0)

	_has_art = _try_load_art()

	if bool(def.get("show_name", true)):
		_label = Label.new()
		_label.position = Vector2(-40, -46)
		_label.add_theme_font_size_override("font_size", 11)
		add_child(_label)

	_apply_animation()
	queue_redraw()


# 实体销毁时释放资源引用(由 EntityView 调用)。
func teardown() -> void:
	if not _sprite_path.is_empty():
		AssetCache.release(_sprite_path)
		_sprite_path = ""


func _try_load_art() -> bool:
	if not ActorDef.has_sprite(def):
		return false
	var path := str(def["sprite"])
	var frames := AssetCache.acquire_frames(path)
	if frames == null:
		return false
	_sprite_path = path

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.name = "Sprite"
	add_child(_sprite)
	_rows = _detect_rows(frames)
	return _rows.size() > 0


# 从已加载的动画名反推美术支持哪些朝向行(如 "walk_side" -> "side")。
func _detect_rows(frames: SpriteFrames) -> Array:
	var found: Array = []
	for row in ROW_CANDIDATES:
		for anim in frames.get_animation_names():
			if anim.ends_with("_" + str(row)):
				found.append(row)
				break
	return found


# 设置朝向(传连续角度, 弧度)。内部量化到 4 向。
func set_facing_radians(radians: float) -> void:
	set_facing_dir(Direction.quantize(radians))


# 设置朝向(传 4 向枚举)。
func set_facing_dir(dir: int) -> void:
	if facing_dir == dir:
		return
	facing_dir = dir
	_apply_animation()


# 设置动作(站立/行走/攻击)。
func set_action(p_action: int) -> void:
	if action == p_action:
		return
	action = p_action
	_apply_animation()


func refresh(entity: Entity) -> void:
	if _label != null:
		_label.text = "%s L%d" % [
			str(entity.get_prop("name", "")), int(entity.get_prop("level", 0))]


# 根据 动作 + 朝向 选动画, 并处理左右镜像。
func _apply_animation() -> void:
	if not _has_art or _sprite == null:
		queue_redraw()
		return

	var pick := Facing.render_for(facing_dir, _rows)
	if pick.is_empty():
		return
	var anim := "%s_%s" % [ACTION_NAMES[action], str(pick["row"])]
	if not _sprite.sprite_frames.has_animation(anim):
		return
	if _sprite.animation != anim:
		_sprite.play(anim)
	_sprite.flip_h = bool(pick["flip"])
	queue_redraw()


# 播放一次性动作(如攻击), 播完自动回到站立。
func play_once(p_action: int) -> void:
	set_action(p_action)
	if _has_art and _sprite != null:
		_sprite.play()
		if not _sprite.animation_finished.is_connected(_on_action_finished):
			_sprite.animation_finished.connect(_on_action_finished)


func _on_action_finished() -> void:
	if action == Action.ATTACK:
		set_action(Action.IDLE)


# 当前朝向对应的单位向量(占位绘制用)。
func _facing_vector() -> Vector2:
	var a := Direction.angle(facing_dir)
	return Vector2(cos(a), sin(a))


# 占位模式绘制(无美术资源时)。画圆 + 朝向箭头, 使朝向可见可验证。
func _draw() -> void:
	if _has_art:
		return
	draw_circle(Vector2.ZERO, _radius, _body_color)
	var tip := _facing_vector() * (_radius + 8.0)
	draw_line(Vector2.ZERO, tip, COLOR_FACING, 2.0)
	draw_circle(tip, 2.0, COLOR_FACING)
