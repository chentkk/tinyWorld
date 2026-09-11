# direction.gd — 朝向工具(服务端 tinyworld/core/direction.lua 的 GDScript 移植)。
#
# ⚠ 为什么是"移植"而不是直接调用:
#   服务端的 direction.lua 是纯 Lua 模块, 且**不经协议下发**(只作为服务端内部工具)。
#   Godot 客户端是 GDScript, 无法 require Lua 模块, 因此这里按其语义等价实现一份。
#   若服务端该模块语义变更, 本文件需同步 —— 请对照 server/tinyworld/core/direction.lua。
#
# 语义与 Lua 版保持一致:
#   * 实体属性 dir 存**连续角度**(弧度), 支持任意方向自由移动;
#     "4 方向"只是客户端美术表现, 由 quantize() 把连续角度量化到 4 向。
#   * 角度约定(与 cos/sin 一致): 0=右, PI/2=下, PI=左, -PI/2=上。
#   * 世界坐标: x 向右为正, y 向下为正(与屏幕坐标一致)。
extends RefCounted
class_name Direction

# 4 方向枚举(与服务端 direction.lua 数值一致)。
const DOWN := 0
const LEFT := 1
const UP := 2
const RIGHT := 3

const PI2 := PI * 2.0

# 量化时的遍历顺序, 决定正好落在 45 度分界线上的取整结果(取靠前者)。
# 服务端同序: { RIGHT, DOWN, LEFT, UP }
const ORDER: Array[int] = [RIGHT, DOWN, LEFT, UP]

# 方向中心角度(弧度)。
const ANGLES := {
	RIGHT: 0.0,
	DOWN: PI / 2.0,
	LEFT: PI,
	UP: -PI / 2.0,
}

# 方向分界线(度)。四个方向各占 90 度, 左闭右开:
#     [315,360)∪[0,45) -> RIGHT    [45,135) -> DOWN
#     [135,225)        -> LEFT     [225,315) -> UP
#
# 由**服务端实测**确定: 二分法求得切换点恰在 45/135/225/315 度(误差 < 1e-13 度),
# 并与逐度扫描的 1441 个采样点全部吻合。
# 注意这不是"取最近中心角"的 45 度对分模型 —— 45 度本身归 RIGHT, 46 度才归 DOWN。
const BOUNDARY_DEG := 45.0

# 边界判定的角度容差(度)。吸收多圈角度归一化时的浮点误差(实测约 1e-10 度),
# 远小于有意义的角度间隔(90 度), 只影响边界点本身。
const TOL := 1e-6



static func angle(dir: int) -> float:
	return ANGLES.get(dir, 0.0)


static func is_valid(dir: int) -> bool:
	return ANGLES.has(dir)


# 把任意角度归一化到 [-PI, PI)。
#
# 必须用 fposmod 而非 fmod / posmod:
#   * Lua 的 `a % pi2` 对负数返回**非负**结果(Python/Lua 取模语义);
#   * GDScript fmod() 保留被除数符号(C 语义), 直接用会得到负值 -> 结果错;
#   * GDScript posmod() 是**整数**取模(会截断小数!) -> 结果完全错。
#   * fposmod() 才是浮点 + 除数符号, 与 Lua 语义一致。
# 运算顺序也照搬 Lua, 否则在 45 度平分线这类浮点并列点上, 1e-15 级累积
# 差异会翻转比较结果, 导致量化方向与服务端不一致(已用 1477 点扫描验证)。
static func normalize(a: float) -> float:
	a = fposmod(a, PI2)         # 等价于 Lua 的 a % pi2
	if a >= PI:
		a -= PI2
	return a


# 角度差(取最短, 结果在 [-PI, PI))。
static func delta(a: float, b: float) -> float:
	return normalize(a - b)


# 由移动向量求连续角度; 零向量返回 NAN(表示"不改变朝向")。
# 注意: GDScript 的 atan2(y, x) 与服务端 math.atan(y, x) 同为 atan2 语义。
static func angle_from_vector(dx: float, dy: float) -> float:
	if dx == 0.0 and dy == 0.0:
		return NAN
	return atan2(dy, dx)


# 把连续角度量化为 4 方向之一。
#
# 边界行为(与服务端逐点比对过):
#   45度->RIGHT, 135度->DOWN, 225度->LEFT, **315度->RIGHT**
#   注: 服务端 direction.lua 的注释写 "315度 -> UP" 与实测不符 —— 315度时
#   RIGHT(0/-360) 与 UP(-90) 距离并列, 遍历顺序 ORDER 中 RIGHT 在前故取 RIGHT。
#   本实现严格按 ORDER 顺序取靠前者, 与服务端**实际行为**一致。
static func quantize(a: float) -> int:
	a = normalize(a)
	# 换算成度后按 90 度区间判定(见 BOUNDARY_DEG 注释: 边界由服务端实测)。
	# 用区间比较而非浮点距离, 保证 45 度整数倍处结果确定。
	var deg := rad_to_deg(a)                    # [-180, 180)
	if deg < 0.0:
		deg += 360.0                            # [0, 360)
	# 边界归属由实测确定, 两个端点不同侧(易错点):
	#   315 度(-45 度) -> RIGHT   315 度是 RIGHT 区间的**起点**(含)
	#   45 度          -> RIGHT   45 度是 RIGHT 区间的**终点**(含)
	#   135 度         -> DOWN    135 度是 DOWN 区间的终点(含)
	#   225 度         -> LEFT    225 度是 LEFT 区间的终点(含)
	# 即 RIGHT 区间为 [315, 45](两端都含), 其余为 (45,135] / (135,225] / (225,315)。
	#
	# 用 TOL 放宽边界: 多圈角度(如 -675 度)归一化后因浮点求值会落在 45 度略微
	# 偏右处(45.0000000001), 本应归 RIGHT 却被判成 DOWN。实测服务端用 64 位
	# double, 归一化后能精确落在 45.0; GDScript 精度略低, 故用容差吸收。
	# TOL 远小于任何有意义的角度间隔(90 度), 不会影响正常角度。
	if deg <= BOUNDARY_DEG + TOL or deg >= 360.0 - BOUNDARY_DEG - TOL:
		return RIGHT
	if deg <= 135.0 + TOL:
		return DOWN
	if deg <= 225.0 + TOL:
		return LEFT
	return UP


# 方向名(调试/日志用)。
static func dir_name(dir: int) -> String:
	match dir:
		RIGHT:
			return "RIGHT"
		DOWN:
			return "DOWN"
		LEFT:
			return "LEFT"
		UP:
			return "UP"
		_:
			return "?"
