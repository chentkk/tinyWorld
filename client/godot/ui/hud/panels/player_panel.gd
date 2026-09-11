# player_panel.gd — 自己角色的核心属性(hp/mp/等级/金币/坐标)。
extends PanelBase
class_name PlayerPanel

# 可选: 由 main 注入"当前渲染位置"的取值函数(返回 Vector2)。
# 因为角色的画面位置来自 MovePredictor(含本地预测与边界限制), 而实体属性里的
# x/y 是服务器**最后确认**的位置, 两者在移动中/边界处会不同。面板显示前者,
# 才能与画面上角色所在位置一致。
var position_provider: Callable = Callable()


func _build_text(world: WorldState, _entity_id: int) -> String:
	var e := world.get_self()
	if e == null:
		return "角色: (未进入世界)"

	var pos_text: String
	if position_provider.is_valid():
		var p: Vector2 = position_provider.call()
		pos_text = "x=%.0f, y=%.0f" % [p.x, p.y]
	else:
		pos_text = "x=%s, y=%s" % [str(e.get_prop("x", "?")), str(e.get_prop("y", "?"))]

	return "L%d  hp=%s/%s  mp=%s/%s  gold=%s  (%s)" % [
		int(e.get_prop("level", 0)),
		str(e.get_prop("hp", "?")), str(e.get_prop("maxHp", "?")),
		str(e.get_prop("mp", "?")), str(e.get_prop("maxMp", "?")),
		str(e.get_prop("gold", 0)),
		pos_text,
	]
