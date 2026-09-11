# predictor.gd — 本地移动预测 + 服务器 Reconciliation。
#
# 核心原则: **预测位置由本模块独占累积, 服务器位置只在收到回包时使用一次。**
#
#   * 每帧:  position += 方向 * speed * dt          (本地推进, 保证画面平滑)
#   * 发送:  累积到一定时长后打包成一条指令发给服务器(带宽考虑, 见 MOVE_SEND_INTERVAL)
#   * 回包:  position = 服务器位置 + 重放(已发未确认指令) + 尚未发送的本地预测
#
# 为什么本地推进和发包要分开:
#   发包不能每帧都发(MMORPG 人多时移动包会打满带宽), 但**画面必须每帧前进**,
#   否则就是一格一格的。因此本地按帧累积, 发包按固定间隔打包(把这段时间的
#   位移合成一条 dt 指令)。
#
# 为什么不能每帧用服务器位置当基准:
#   服务器位置(prop props)每 ~100ms 才更新一次。若每帧都用"服务器位置 + 一步"
#   来算渲染位置, 两次回包之间服务器位置是静止的旧值, 每帧算出的位置几乎不动,
#   回包瞬间再猛跳一个 tick 的量 —— 表现为严重的"被拉"。
#
# 速度必须与服务端一致(服务端 Move:onTick 用 entity:get("speed") 推演),
# 否则预测与权威位置有系统性偏差, 回包时会周期性拽动。故 speed 由外部用
# 服务端下发的属性设置, 不硬编码。
extends RefCounted
class_name MovePredictor

# 服务端未下发 speed 时的兜底值(见 server/game/def/player/attrs.lua 的默认 6)。
const DEFAULT_SPEED := 6.0

var speed: float = DEFAULT_SPEED
# 服务器已确认的最后移动序号(回包里带的 seq)。
var server_seq: int = 0
# 当前预测位置(渲染的唯一来源)。
var position: Vector2 = Vector2.ZERO
# 最近一次 reconcile 造成的**净位置变化**(服务器校正量)。供 HUD 实时显示,
# 便于观察"被往回拉"。每次 advance(纯本地推进)后清零。
var last_correction: Vector2 = Vector2.ZERO

var _pending: Array = []          # 已发送、尚未被服务器确认的指令
var _next_seq: int = 0
# 尚未打包发送的本地预测。**不变式: 这段时长内方向恒定** ——
# 方向一变就立刻打包发送(见 main.gd), 故 _unsent_dir 可代表整段 _unsent_dt。
var _unsent_dir: Vector2 = Vector2.ZERO
var _unsent_dt: float = 0.0
var _initialized := false
# 世界边界: **不使用**。
#
# 服务端 Move:onTick 直接用 entity:set("x") 写坐标, 绕过了 RealEntity:setPosition
# 里的 space.bounds clamp, 因此服务端实际上允许玩家跑出 space 范围(实测 x 可达
# 17000, 而 space 只有 2000)。客户端若按 spaceInfo 自行 clamp, 会把渲染位置
# 永久钉在边界上 —— 表现为"怎么移动画面都不变", 比越界本身更糟。
# 故这里保留接口但默认不启用; 待服务端修好边界限制后再打开。
var _bounds_min := Vector2.ZERO
var _bounds_max := Vector2.ZERO
var _clamp_enabled := false


# 设置世界边界(来自 ACCOUNT spaceInfo 的 width/height)。
# 目前仅记录, 不做限制(原因见上)。服务端修复边界后可把 _clamp_enabled 置 true。
func set_bounds(width: float, height: float) -> void:
	if width > 0.0 and height > 0.0:
		_bounds_min = Vector2.ZERO
		_bounds_max = Vector2(width, height)


func _clamp_to_bounds(p: Vector2) -> Vector2:
	if not _clamp_enabled or _bounds_max == Vector2.ZERO:
		return p
	return Vector2(
		clampf(p.x, _bounds_min.x, _bounds_max.x),
		clampf(p.y, _bounds_min.y, _bounds_max.y))


# 由服务端下发的 speed 属性更新预测速度。
# 传入非正数或非数字则退回默认值, 避免零/负速度导致预测不动或倒退。
func set_speed(value: Variant) -> void:
	var v := float(value) if (value is float or value is int) else DEFAULT_SPEED
	speed = v if v > 0.0 else DEFAULT_SPEED


# 进入世界 / 重连后, 用服务端权威位置作为预测起点。
func reset_to(pos: Vector2) -> void:
	position = _clamp_to_bounds(pos)
	_pending.clear()
	_next_seq = 0
	server_seq = 0
	_unsent_dir = Vector2.ZERO
	_unsent_dt = 0.0
	_initialized = true


func reset() -> void:
	_pending.clear()
	_next_seq = 0
	server_seq = 0
	_unsent_dir = Vector2.ZERO
	_unsent_dt = 0.0
	_initialized = false


func is_ready() -> bool:
	return _initialized


func has_pending() -> bool:
	return _pending.size() > 0


# 尚未打包发送的时长(秒)。main 用它判断是否该发包。
func unsent_dt() -> float:
	return _unsent_dt


# 本地推进一帧。只影响本地预测位置, 不分配 seq、不发送。
# dt 由调用方按服务端上限(MOVE_DT_MAX)截断, 保证与服务器推演的时长一致。
func advance(dir: Vector2, dt: float) -> void:
	if dt <= 0.0:
		return
	position = _clamp_to_bounds(position + dir * speed * dt)
	# 方向恒定的不变式由调用方保证(方向变化时先 take_command)。
	_unsent_dir = dir
	_unsent_dt += dt


# 把累积的本地预测打包成一条指令, 记录为"已发未确认"并返回, 供发送给服务器。
# 无待发时长时返回空字典。
func take_command() -> Dictionary:
	if _unsent_dt <= 0.0:
		return {}
	_next_seq += 1
	var cmd := {
		"seq": _next_seq,
		"dx": _unsent_dir.x,
		"dy": _unsent_dir.y,
		"dt": _unsent_dt,
	}
	_pending.append(cmd)
	_unsent_dt = 0.0
	return cmd


# 服务器权威位置到达(server_pos, 最近处理的指令序号 seq)。
#
# 这是**唯一**使用服务器位置的时机, 标准 Reconciliation:
#   1. 位置设为服务器下发的 (x, y);
#   2. 丢弃 pending 中已被确认的指令(seq <= 服务器序号);
#   3. 重放剩余未确认指令 —— 它们服务器还没处理, 必须补上, 否则每帧被拉回;
#   4. 再加上尚未发送的本地预测(同理, 服务器还不知道)。
#
# server_pos 直接取自 Entity.props 的 (x, y)。服务端 prop 是**增量下发**
# (只含变化字段, 沿 y 走时不发 x), 但客户端的 props 是增量**合并**的,
# 未变的 x 仍保留在 props 里 —— 因此 entity.position() 天然就是
# "服务器最新坐标", 无需额外区分哪些分量本次下发过。
func reconcile(server_pos: Vector2, seq: int) -> Vector2:
	if seq > server_seq:
		server_seq = seq

	# 位置 = 服务器最新坐标 + 重放未确认指令 + 尚未发送的预测。
	# 注意是**重算**而非在旧 position 上增量修改: 旧 position 里已经含有
	# pending 的位移, 若拿它当基准再重放就会重复累加(会表现为未下发分量
	# 凭空被校正、快速转向时画面抽动)。
	var pos := server_pos
	var keep: Array = []
	for cmd in _pending:
		if int(cmd["seq"]) > server_seq:
			keep.append(cmd)
			pos += _delta_of(cmd)
	_pending = keep
	pos += _unsent_dir * speed * _unsent_dt

	var before := position
	position = _clamp_to_bounds(pos)
	# 本次 reconcile 造成的**净位置变化**, 即玩家能看到的"被拉动量"。
	last_correction = position - before
	return position


# 停止移动: 丢弃**尚未发送**的累积量。
#
# 注意**不能**清空 _pending: 那些指令已经发给服务器了, 服务器可能还没处理完。
# 若在此清空, 服务器稍后处理它们时位置会前进, 而客户端已无指令可重放,
# 于是 reconcile 把客户端往回拉 —— 表现为"松手时被拽一下"
# (实测: 一次 80 单位的回拉 = 150 单位/秒 × 0.53 秒的未确认累积)。
# 已发送指令会在服务器回包确认后由 reconcile 自动丢弃, 无需在此处理。
func clear_pending() -> void:
	_unsent_dt = 0.0


func _delta_of(cmd: Dictionary) -> Vector2:
	return Vector2(float(cmd["dx"]), float(cmd["dy"])) * speed * float(cmd["dt"])
