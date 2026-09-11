# crosshair.gd — 施法准星。
#
# 位置 = 角色位置 + 朝向 * 距离, 因此它随角色转向而移动, 直观表示"技能指向哪"。
# 距离可用鼠标滚轮调整(见 main.gd), 用于在不同技能射程间切换。
#
# 用途: 点击时选取**离准星最近的实体**作为 targetId 施法。
#
# 已知限制(协议层面, 非客户端可解):
#   服务端 CombatAgent:onCastAbility 只接受 { targetId, index }, **没有位置参数**,
#   因此准星无法指定"地面坐标"(即真正的点地施法)。像 ability_frost_orb /
#   ability_toxic_pool 这类在服务端按施法者朝向自行计算落点的技能, 客户端只能
#   通过转向来间接影响落点方向, 不能精确指定位置。
#   若要做点地施法, 需要服务端在 onCastAbility 增加位置字段。
extends Node2D
class_name Crosshair

const COLOR_OK := Color(1.0, 0.9, 0.3, 0.95)      # 准星附近有可选目标
const COLOR_IDLE := Color(0.7, 0.75, 0.8, 0.65)   # 附近无目标
const RADIUS := 10.0
const LOCK_RADIUS := 6.0

# 距离标注的字体大小。
const LABEL_SIZE := 12

const GUIDE_COLOR := Color(1.0, 0.9, 0.3, 0.18)   # 角色->准星 的引导线

var _has_target := false
var _distance := 150.0
# 角色所在位置。用于画一条从角色指向准星的引导线, 让"瞄准方向"更直观
# (仅有准星点时方向感偏弱)。由 main 每帧设置。
var _origin := Vector2.ZERO


func set_origin(origin: Vector2) -> void:
	_origin = origin


func set_distance(distance: float) -> void:
	_distance = distance
	queue_redraw()


func get_distance() -> float:
	return _distance


# 由 main 每帧告知"准星附近是否有可选目标", 用于切换颜色。
func set_has_target(value: bool) -> void:
	if _has_target == value:
		return
	_has_target = value
	queue_redraw()


func _draw() -> void:
	var color := COLOR_OK if _has_target else COLOR_IDLE

	# 引导线: 从角色指向准星。准星节点自身位于准星处, 故角色方向为 _origin - position。
	# 先画, 避免盖住刻线。
	if _origin != position:
		draw_line(_origin - position, Vector2.ZERO, GUIDE_COLOR, 1.0)

	# 四段准星刻线(避免中心遮挡目标)
	var gap := RADIUS * 0.35
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(dir * gap, dir * RADIUS, color, 2.0)

	# 外圈(锁定目标时更醒目)
	if _has_target:
		draw_arc(Vector2.ZERO, RADIUS + 3.0, 0.0, TAU, 24, color, 1.5)

	# 距离标注(显示在准星右下方)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(RADIUS + 4.0, RADIUS + 12.0),
		"%d" % int(_distance), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)


# 从角色位置按下朝向推进, 得到准星的世界坐标。
# 这里用方向向量而非 4 向枚举: 准星是"瞄准方向", 应连续跟随朝向(自由移动)。
static func position_for(origin: Vector2, facing_radians: float, distance: float) -> Vector2:
	return origin + Vector2(cos(facing_radians), sin(facing_radians)) * distance
