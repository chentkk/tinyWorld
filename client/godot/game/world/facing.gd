# facing.gd — 朝向的**渲染映射**层。
#
# 分工:
#   Direction (core/protocol/direction.gd)  —— 连续角度 -> 4 方向枚举(服务端权威语义)
#   Facing    (本文件)                       —— 4 方向枚举 -> 美术行 + 是否水平翻转
#
# 服务端 dir 是**连续角度**(任意方向自由移动), 客户端用 Direction.quantize() 量化到
# 4 向(RIGHT/DOWN/LEFT/UP)后选美术。自己用本地输入预测以获得无延迟转向, 服务器
# prop 回来后以服务端值为准。
#
# 两种美术布局都支持(由序列帧描述文件的 directions 声明决定):
#   4 行: ["down","up","left","right"]  —— 每个方向独立绘制, 不需要翻转
#   3 行: ["down","up","side"]          —— side 画"朝右", 朝左由 flip_h 镜像
extends RefCounted
class_name Facing

# 方向枚举 -> 序列帧描述文件里的行名。
const ROW_NAMES := {
	Direction.DOWN: "down",
	Direction.UP: "up",
	Direction.LEFT: "left",
	Direction.RIGHT: "right",
}

# 布局不含 "left" 时的退路: 用这一行 + 水平翻转表示朝左。
const SIDE_ROW := "side"


# 连续角度(弧度) -> 4 方向枚举。委托给 Direction, 保证与服务端 quantize 一致。
static func quantize(radians: float) -> int:
	return Direction.quantize(radians)


# 方向向量 -> 4 方向枚举。零向量返回 fallback(不改变朝向)。
static func quantize_vector(v: Vector2, fallback: int = Direction.RIGHT) -> int:
	if v.length_squared() < 0.0001:
		return fallback
	return Direction.quantize(Direction.angle_from_vector(v.x, v.y))


# 给定量方向枚举与序列帧描述文件声明的行名列表, 求出该用哪一行、是否翻转。
# 返回 { "row": String, "flip": bool }; 行名不存在于 directions 时返回 {}。
static func render_for(dir: int, directions: Array) -> Dictionary:
	var want := str(ROW_NAMES.get(dir, "down"))

	# 1) 优先直接匹配(4 行布局, 或 3 行布局里的 down/up)。
	if directions.has(want):
		return { "row": want, "flip": false }

	# 2) 退路: 朝左用 side 行翻转(3 行布局)。
	if dir == Direction.LEFT and directions.has(SIDE_ROW):
		return { "row": SIDE_ROW, "flip": true }

	# 3) 再退路: 有 side 行且朝向是水平方向。
	if directions.has(SIDE_ROW) and (dir == Direction.RIGHT or dir == Direction.LEFT):
		return { "row": SIDE_ROW, "flip": dir == Direction.LEFT }

	# 4) 最后: 用第一行兜底, 避免美术缺行时整个不显示。
	if directions.size() > 0:
		return { "row": str(directions[0]), "flip": false }
	return {}
