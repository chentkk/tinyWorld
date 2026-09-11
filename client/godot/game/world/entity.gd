# entity.gd — 客户端侧的实体(玩家/投掷物/...)。
# 由 WorldState 根据 object add / prop 消息维护; 视觉表现由 ui/ 层订阅信号后自行处理。
extends RefCounted
class_name Entity

var entity_id: int = 0
var kind: String = ""
var is_self: bool = false

# 服务器同步来的属性快照(x, y, hp, maxHp, level, name, speed, ...)。
var props: Dictionary = {}

# 自己移动时, 服务器回包携带的最后处理序号(Reconciliation 用)。
var last_seq: int = 0
# 其他实体最近一次位置更新, 供 ui 层做插值。
var prev_pos: Vector2 = Vector2.ZERO
var has_prev_pos: bool = false


func _init(p_id: int = 0, p_kind: String = "", p_self: bool = false) -> void:
	entity_id = p_id
	kind = p_kind
	is_self = p_self


# 属性读取; 缺省返回 fallback。
func get_prop(name: String, fallback: Variant = null) -> Variant:
	return props.get(name, fallback)


func position() -> Vector2:
	return Vector2(float(props.get("x", 0.0)), float(props.get("y", 0.0)))


func apply_props(changed: Dictionary) -> void:
	# 记录旧位置, 供插值使用。
	if changed.has("x") or changed.has("y"):
		prev_pos = position()
		has_prev_pos = true
	for k in changed.keys():
		props[k] = changed[k]


func is_moving_prop(changed: Dictionary) -> bool:
	return changed.has("x") or changed.has("y")
