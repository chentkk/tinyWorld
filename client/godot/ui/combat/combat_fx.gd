# combat_fx.gd — 战斗表现层: 伤害/治疗飘字。
# 订阅服务器推送的战斗事件(onCombatDamage / onCombatHeal), 在对应实体位置生成飘字。
extends Node2D
class_name CombatFx

const FLOAT_TTL := 1.0
const FLOAT_RISE := 40.0     # 飘字每秒上浮像素
const SPAWN_OFFSET := Vector2(0, -20)

const COLOR_DAMAGE := Color(1, 0.3, 0.3)
const COLOR_HEAL := Color(0.3, 1, 0.4)

# entityId -> Node2D, 由外部注入(用于定位飘字)。
var entity_nodes: Dictionary = {}


# 处理一条 RPC 事件; 返回是否已消费(未消费的事件由调用方另行处理)。
func handle_rpc(method: String, d: Dictionary) -> bool:
	match method:
		Protocol.EV_COMBAT_DAMAGE:
			_spawn(d, "-%s" % str(d.get("amount", "")), COLOR_DAMAGE)
			return true
		Protocol.EV_COMBAT_HEAL:
			_spawn(d, "+%s" % str(d.get("amount", "")), COLOR_HEAL)
			return true
	return false


func _spawn(d: Dictionary, text: String, color: Color) -> void:
	var id := int(d.get("entityId", 0))
	var pos := Vector2.ZERO
	var node: Node2D = entity_nodes.get(id)
	if node != null:
		pos = node.position

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.position = pos + SPAWN_OFFSET

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - FLOAT_RISE, FLOAT_TTL)
	tween.tween_property(label, "modulate:a", 0.0, FLOAT_TTL)
	tween.chain().tween_callback(label.queue_free)

	add_child(label)


func clear() -> void:
	for child in get_children():
		child.queue_free()
