# main.gd — 客户端入口: 装配各层 + 输入 + 主循环。
#
# 分层约定(依赖单向, 上层可依赖下层, 下层不知道上层):
#   core/  框架层  —— 协议、帧编解码、TCP、HTTP(与玩法无关)
#   game/  玩法层  —— 登录状态机、世界状态、移动预测
#   ui/    表现层  —— HUD、面板、实体/网格/飘字绘制
#   scripts/main.gd —— 只做装配与转发, 不含业务细节
#
# 依赖注入: 各模块由本文件显式创建并互相连接, 不使用 autoload 全局单例,
# 使依赖关系可见、可测试。
extends Node2D

const TcpClient := preload("res://core/net/tcp_client.gd")
const LoginFlow := preload("res://game/session/login_flow.gd")
const WorldState := preload("res://game/world/world_state.gd")
const MovePredictor := preload("res://game/movement/predictor.gd")
const EntityView := preload("res://ui/world/entity_view.gd")
const MapView := preload("res://ui/world/map_view.gd")
const WorldReady := preload("res://game/world/world_ready.gd")
const SessionPhase := preload("res://game/session/session_phase.gd")
const Crosshair := preload("res://ui/world/crosshair.gd")
const CombatFx := preload("res://ui/combat/combat_fx.gd")
const Hud := preload("res://ui/hud/hud.gd")

# 摄像机相对角色的偏置(世界单位)。摄像机右移 => 角色显示在屏幕中心偏左,
# 前方(右侧)可见范围更大。
# 取 120: 1280 宽视口下角色落在屏幕 x≈520, 距左侧 420px 宽的 HUD 面板还有
# 100px 余量(偏置再大就会贴到面板边缘), 同时右侧视野多出 120px。
const CAMERA_BIAS := Vector2(120, 0)

# 准星距离的可调范围与步进(鼠标滚轮)。
const CROSSHAIR_MIN := 40.0
const CROSSHAIR_MAX := 800.0
const CROSSHAIR_STEP := 20.0
# 准星"锁定"目标的判定半径: 该范围内的最近实体即被锁定。
const CROSSHAIR_LOCK_RANGE := 60.0
# 数字键施法时, 若准星未锁定目标, 退而取自身附近该范围内的最近实体。
const CAST_FALLBACK_RANGE := 400.0

# 服务器地址与账号(可被命令行覆盖)。
var host := "127.0.0.1"
var account := "test1"
var password := "123456"

# 无人值守验证用。
var auto_move := false
var auto_cast := false
var auto_quit_after := 0.0
# 摄像机是否跟随角色。调试时可关闭(画面固定), 便于判断角色是否被服务器回拉。
var camera_follow := true
var _script_move := false
var _script_zigzag := false
var _script_t := 0.0
# 关闭跟随时, 摄像机是否已完成首次定位。
var _camera_locked := false

# ---- 各层实例 ----
var _tcp: TcpClient
var _login: LoginFlow
var _world: WorldState
var _predictor: MovePredictor
var _map: MapView
var _crosshair: Crosshair
var _entity_view: EntityView
var _combat_fx: CombatFx
var _hud: Hud
var _camera: Camera2D

# ---- 阶段与就绪 ----
var _phase: SessionPhase
var _ready_gate: WorldReady

# ---- 输入状态 ----
var _moving := false
var _next_task_id := 99001
var _quit_timer := 0.0
var _quit_done := false
var _auto_cast_done := false
# HUD 实时坐标: 上一帧位置, 用于算帧位移。
var _last_readout_pos := Vector2.ZERO
# 朝向: 最后一次移动方向(停下时保持朝向)与当前连续角度(弧度)。
var _last_heading := Vector2.ZERO
var _local_dir: float = 0.0    # 本地预测朝向; 服务器 prop 回来后被覆盖
# 当前已开始累积(但可能尚未发出)的移动方向。方向变化时立即冲刷, 保证
# 每个移动包内方向恒定(见 _push_move)。
var _sent_dir := Vector2.ZERO
# 准星距角色的距离(鼠标滚轮调整)。
var _crosshair_dist := 150.0
# 准星当前锁定的目标 entityId(0 = 无)。点击时若无锁定目标, 则取准星附近最近的。
var _crosshair_target := 0


func _ready() -> void:
	_parse_args()
	_build_layers()
	_connect_signals()
	_login.start(host, account, password)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--account="):
			account = a.get_slice("=", 1)
		elif a.begins_with("--host="):
			host = a.get_slice("=", 1)
		elif a == "--auto-move":
			auto_move = true
		elif a == "--cast":
			auto_cast = true
		elif a == "--script-zigzag":
			# 复现"快速交替 A/W(左上)": 每 ~0.13s 切换一次方向
			_script_zigzag = true
		elif a == "--script-move":
			# 脚本化移动: 先向右 1.2s, 再向下 1.2s。复现"水平->垂直"转向场景。
			_script_move = true
		elif a == "--no-camera-follow":
			# 关闭跟随后, 摄像机在进入世界时**定位到角色初始位置**并从此不动。
			# (不能固定在世界中心: 角色可能早已在世界之外, 那样根本不在画面里。)
			camera_follow = false
		elif a.begins_with("--auto-quit="):
			auto_quit_after = float(a.get_slice("=", 1))


# ---- 装配 ----
func _build_layers() -> void:
	# 世界层(地图网格 -> 实体 -> 战斗特效, 保证绘制顺序)。
	# 地图有独立的加载/卸载生命周期(见 MapView), 切图时不会残留。
	_map = MapView.new()
	_map.name = "MapView"
	add_child(_map)

	_entity_view = EntityView.new()
	_entity_view.name = "EntityView"
	add_child(_entity_view)

	_combat_fx = CombatFx.new()
	_combat_fx.name = "CombatFx"
	_combat_fx.entity_nodes = _entity_view.entity_nodes
	add_child(_combat_fx)

	# 准星画在实体之上, 保证任何情况下都能看到。
	_crosshair = Crosshair.new()
	_crosshair.name = "Crosshair"
	_crosshair.z_index = 100
	add_child(_crosshair)

	_camera = Camera2D.new()
	_camera.name = "Camera"
	add_child(_camera)
	_camera.make_current()

	# HUD(CanvasLayer, 不受摄像机影响)。
	# 注入位置取值函数: 面板坐标显示"渲染位置"(含预测与边界限制), 与画面一致。
	_hud = Hud.new()
	_hud.name = "Hud"
	_hud.position_provider = func() -> Vector2: return _predictor.position
	add_child(_hud)

	# 逻辑层。
	_tcp = TcpClient.new()
	_world = WorldState.new()
	_predictor = MovePredictor.new()
	_login = LoginFlow.new(_tcp)
	_phase = SessionPhase.new()
	_ready_gate = WorldReady.new(_world)


func _connect_signals() -> void:
	# 登录状态机。
	_login.logged.connect(_hud.log)
	_login.failed.connect(_on_login_failed)
	_login.entered_world.connect(_on_entered_world)
	_login.state_changed.connect(_on_login_state_changed)
	# 空间几何: 加载地图(网格 + 世界边界)。
	_login.space_info.connect(_on_space_info)
	# 初始数据齐全 -> 进入可游玩状态。
	_ready_gate.became_ready.connect(_on_world_ready)
	_phase.changed.connect(_on_phase_changed)

	# 世界状态 -> 表现层。
	_world.entity_added.connect(_on_entity_added)
	_world.entity_removed.connect(_entity_view.remove_entity)
	_world.props_changed.connect(_on_props_changed)
	_world.record_changed.connect(_on_data_changed)
	_world.view_changed.connect(_on_data_changed)

	# 收发: TCP 消息同时喂给登录状态机与业务分发。
	_tcp.message.connect(_on_tcp_message)


# ---- 消息分发 ----
# 登录阶段的消息由 LoginFlow 消费; 世界同步与 RPC 事件由这里分发。
func _on_tcp_message(msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	if t == Protocol.T_OBJECT or t == Protocol.T_PROP \
			or t == Protocol.T_RECORD or t == Protocol.T_VIEW:
		_world.apply_message(msg)
	elif t == Protocol.T_RPC:
		_on_rpc(str(msg.get("n", "")), msg.get("d", {}))


func _on_rpc(method: String, d: Dictionary) -> void:
	if _combat_fx.handle_rpc(method, d):
		return
	if method == Protocol.EV_SPELL_CAST:
		_hud.log("施法: %s -> %s" % [
			str(d.get("abilityName", "")), str(d.get("targetId", ""))])
		# 服务器广播的施法事件: 让施法者播一次攻击动作(含其他玩家)。
		_entity_view.play_attack(int(d.get("entityId", 0)))


# ---- 登录/世界事件 ----
func _on_login_state_changed(state: int) -> void:
	match state:
		LoginFlow.State.CONNECTING:
			_hud.set_status("连接 gate...")
		LoginFlow.State.AUTHING:
			_hud.set_status("鉴权中...")
		LoginFlow.State.ENTERING:
			_hud.set_status("进入世界...")
		LoginFlow.State.WORLD:
			_hud.set_status("已进入世界 (selfId=%d)" % _world.self_id)
		LoginFlow.State.IDLE:
			_hud.set_status("未连接 (按 R 重连)")


func _on_login_failed(message: String) -> void:
	_hud.set_status("失败: %s" % message)
	_world.clear()
	_entity_view.clear()
	_combat_fx.clear()
	_predictor.reset()


func _on_entered_world(self_id: int) -> void:
	# 注意: 这里只代表"实体已创建", 初始数据(背包/技能等)可能还没到齐,
	# 因此进入 SYNCING 而非直接 PLAYING —— 由 WorldReady 决定何时可玩。
	_phase.set_phase(SessionPhase.Phase.SYNCING)
	_hud.set_status("同步初始数据...")


# 地图几何到达 -> 加载地图(卸载旧图, 保证切图不残留)。
func _on_space_info(width: float, height: float) -> void:
	_map.load_map({ "id": "main", "width": width, "height": height })


# 初始数据齐全 -> 可游玩。游戏内逻辑模块从这里开始执行。
func _on_world_ready(missing: Array) -> void:
	if not missing.is_empty():
		_hud.log("初始数据超时, 缺失: %s" % str(missing))
	_phase.set_phase(SessionPhase.Phase.PLAYING)
	_hud.set_status("可开始游戏 (selfId=%d)" % _world.self_id)


func _on_phase_changed(from: int, to: int) -> void:
	_hud.log("阶段: %s -> %s" % [_phase.name_of(from), _phase.name_of(to)])


func _on_entity_added(entity: Entity) -> void:
	if entity.is_self:
		# 服务端在 object add 的 props 里下发 speed; 本地预测必须用同一速度,
		# 否则预测与服务器推演有系统性偏差, 回包时会顿挫(见 predictor.gd)。
		_predictor.set_speed(entity.get_prop("speed", MovePredictor.DEFAULT_SPEED))
		# 以服务端权威位置作为预测起点。
		_predictor.reset_to(entity.position())
	_entity_view.add_entity(entity)
	if entity.is_self:
		_entity_view.set_self_position(_predictor.position)
	_hud.refresh(_world)


func _on_props_changed(entity: Entity, changed: Dictionary) -> void:
	if entity.is_self:
		# 速度可能被服务端改动(增益/减速), 跟随更新, 保证预测与推演一致。
		if changed.has("speed"):
			_predictor.set_speed(entity.get_prop("speed", MovePredictor.DEFAULT_SPEED))
		# 服务器权威位置 + 最近处理的指令序号 -> Reconciliation。
		# 服务器只在"位置更新包"里附带 seq(见 cell.lua 的 deliverToPlayer), 故
		# seq 必然与 x/y 同现; 仅在位置变化时校正, 避免拿陈旧 seq 回滚预测。
		#
		# entity.position() 取自 Entity.props, 而 props 是**增量合并**的(只覆盖
		# 本次下发的字段), 因此它天然就是"服务器最新坐标" —— 服务端虽然只发
		# 变化字段(沿 y 走时不发 x), 未变的 x 仍保留在 props 里, 无需额外处理。
		if changed.has("x") or changed.has("y"):
			_predictor.reconcile(entity.position(), entity.last_seq)
			_entity_view.set_self_position(_predictor.position)
		# 朝向以服务端为准(本地预测只用于"按下到回包之间"的无延迟转向)。
		if changed.has("dir"):
			_local_dir = float(entity.get_prop("dir", _local_dir))
			_entity_view.set_self_facing(_local_dir, _moving)
	else:
		_entity_view.update_entity(entity, changed)
	_hud.refresh(_world)


func _on_data_changed(_entity_id: int, _name: String, _ops: Array) -> void:
	_hud.refresh(_world)


# 每帧刷新 HUD 的实时坐标读数(世界状态变化不频繁, 无法反映逐帧移动)。
# 显示本帧位移: 若某帧位移与移动方向相反, 就是被服务器回拉了。
func _update_pos_readout(_delta: float) -> void:
	var pos := _predictor.position
	_hud.update_position(pos, pos - _last_readout_pos, _predictor.last_correction)
	_last_readout_pos = pos


# ---- 主循环 ----
func _process(delta: float) -> void:
	_tcp.poll()

	# 就绪判定: 只有进入世界后才检查(它依赖世界数据)。
	if _phase.is_in_world():
		_ready_gate.poll(delta)

	# 渲染/移动在"已进入世界"后即可开始(SYNCING 也算), 不必等数据齐全 ——
	# 但**游戏内逻辑模块**请以 _phase.is_playable() 为准。
	if _phase.is_in_world():
		_process_movement(delta)
		_process_auto_cast()
		_follow_self()
		_update_pos_readout(delta)

	_quit_timer += delta
	if auto_quit_after > 0.0 and not _quit_done:
		if _quit_timer >= auto_quit_after:
			_quit_done = true
			_hud.log("auto quit after %.1fs" % _quit_timer)
			_login.close()
			get_tree().quit()


func _process_movement(delta: float) -> void:
	var dir := _read_move_dir()
	if _script_zigzag:
		_script_t += delta
		# 每 0.13 秒在 左 与 上 之间切换(0.13s ≈ 8 帧, 与快速点按接近)
		dir = Vector2(-1, 0) if fmod(_script_t, 0.26) < 0.13 else Vector2(0, -1)
	elif _script_move:
		_script_t += delta
		# 复现"走走停停": 0.6s 走, 0.3s 停, 循环
		var phase := fmod(_script_t, 0.9)
		dir = Vector2(1, 0) if phase < 0.6 else Vector2.ZERO
	elif auto_move and dir == Vector2.ZERO:
		dir = Vector2(1, 0)

	# 朝向与动作由本地输入立即驱动(不等服务器回包, 转向无延迟)。
	# 自己这里用输入预测; 服务器 prop 回来后以服务端 dir 为准(见 _on_props_changed)。
	var heading := dir if dir != Vector2.ZERO else _last_heading
	if heading != Vector2.ZERO:
		_local_dir = Direction.angle_from_vector(heading.x, heading.y)
	_entity_view.set_self_facing(_local_dir, dir != Vector2.ZERO)

	if dir == Vector2.ZERO:
		if _moving:
			_moving = false
			# 停止前把未发出的量补发, 避免服务器少走一小段。
			_flush_move()
			_predictor.clear_pending()
			_sent_dir = Vector2.ZERO
			# **不发 onStopMove**:
			#   服务端的 onStopMove 是无条件清空队列(self.queue = {}),
			#   刚 flush 的移动包若与它落在同一 tick 就会被一起清掉 ——
			#   那段位移服务器从未推演, 而客户端已本地预测走过, 下次 reconcile
			#   就会把客户端往回拉。实测(走走停停 6 秒): 发 onStopMove 时
			#   6 次大校正/累计 74.5 单位/最大 12.5; 不发则三者均为 0。
			#   客户端停止输入后不再发移动包, 服务器 tick 处理完队列即自然停下,
			#   无需 onStopMove。
		return

	_last_heading = dir
	_moving = true
	_push_move(dir.normalized(), delta)


func _push_move(dir: Vector2, delta: float) -> void:
	# 方向变了: 先把上一方向的累积量发出去。
	# 这样每个包内的方向恒定, 服务器不会用错误的方向推演整段时间。
	if dir != _sent_dir:
		_flush_move()
		_sent_dir = dir

	# 本地推进: **每帧**进行, 保证画面平滑(发包频率不影响这个)。
	var dt := minf(delta, Protocol.MOVE_DT_MAX)
	_predictor.advance(dir, dt)
	_entity_view.set_self_position(_predictor.position)

	# 发包: 累积到 MOVE_SEND_INTERVAL 才打包发送(降低带宽);
	# 若累积量已达单包上限则立即发, 避免超出服务器 0.2 的截断。
	var unsent := _predictor.unsent_dt()
	if unsent >= Protocol.MOVE_SEND_INTERVAL or unsent >= Protocol.MOVE_DT_MAX:
		_flush_move()


func _flush_move() -> void:
	var cmd := _predictor.take_command()
	if cmd.is_empty():
		return
	_tcp.send_rpc(Protocol.RPC_MOVE, {
		"seq": cmd["seq"], "dt": cmd["dt"], "dirX": cmd["dx"], "dirY": cmd["dy"] })


func _follow_self() -> void:
	# 必须跟随**预测位置**(每帧更新), 而不是 entity.position()(服务器权威位置,
	# 每 ~100ms 才更新一次)。否则角色本身平滑移动、摄像机却每 100ms 跳一次,
	# 画面上的表现就是"角色被反复拉回原地"。
	#
	# 再加一个偏置: 摄像机位于角色右方, 于是角色显示在屏幕中心**偏左**, 前方
	# (右侧)可见范围更大。鼠标换算世界坐标读的也是 _camera.position, 故加了
	# 偏置后依然一致, 无需另做修正。
	if not _predictor.is_ready():
		return
	# 摄像机跟随可用 --no-camera-follow 关闭(调试用): 画面固定后, 角色是否被
	# 服务器回拉可以直接看出来, 排除摄像机的干扰。
	# 关闭时只在首帧定位一次(对准角色), 之后不再移动。
	if camera_follow:
		_camera.position = _predictor.position + CAMERA_BIAS
	elif not _camera_locked:
		_camera_locked = true
		_camera.position = _predictor.position + CAMERA_BIAS
	# cell 高亮与准星始终更新(与摄像机是否跟随无关)。
	_map.set_focus(_predictor.position)
	_update_crosshair()


# 准星每帧跟随角色的**当前朝向**(本地预测值, 故转向无延迟)。
func _update_crosshair() -> void:
	_crosshair.position = Crosshair.position_for(
		_predictor.position, _local_dir, _crosshair_dist)
	_crosshair.set_origin(_predictor.position)
	_crosshair.set_distance(_crosshair_dist)
	_crosshair_target = _nearest_to(_crosshair.position, CROSSHAIR_LOCK_RANGE)
	_crosshair.set_has_target(_crosshair_target != 0)


func _read_move_dir() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	return dir


# ---- 输入 ----
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_handle_key((event as InputEventKey).keycode)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_cast_at_mouse(mb.position)
			MOUSE_BUTTON_WHEEL_UP:
				_adjust_crosshair(CROSSHAIR_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_crosshair(-CROSSHAIR_STEP)


# 调整准星距离(滚轮)。准星越远, 能瞄到越远的目标。
func _adjust_crosshair(delta_dist: float) -> void:
	_crosshair_dist = clampf(_crosshair_dist + delta_dist, CROSSHAIR_MIN, CROSSHAIR_MAX)
	_hud.log("准星距离 %.0f" % _crosshair_dist)


func _handle_key(key: int) -> void:
	if not _phase.is_in_world():
		if key == KEY_R:
			_hud.log("重新登录...")
			_login.start(host, account, password)
		return

	match key:
		KEY_R:
			_hud.log("重新登录...")
			_login.start(host, account, password)
		KEY_T:
			_next_task_id += 1
			_tcp.send_rpc(Protocol.RPC_ACCEPT_TASK, { "taskid": _next_task_id })
			_hud.log("发送 onAcceptTask taskid=%d" % _next_task_id)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			_cast_ability(key - KEY_1 + 1)


# ---- 施法 ----
# 数字键施法: 目标优先取**准星锁定**的实体, 没有则取自身附近最近的。
# 这样"准星指向谁就打谁", 与鼠标点击的语义一致。
func _cast_ability(index: int) -> void:
	var abilities := _world.abilities(_world.self_id)
	if index < 1 or index > abilities.size():
		_hud.log("技能 %d 不存在 (共 %d 个)" % [index, abilities.size()])
		return
	var target := _crosshair_target
	if target == 0:
		target = _nearest_to(_predictor.position, CAST_FALLBACK_RANGE)
	var d := { "index": index }
	if target != 0:
		d["targetId"] = target
		_face_entity(target)
	_tcp.send_rpc(Protocol.RPC_CAST_ABILITY, d)
	_hud.log("施放技能 %d (target=%s)" % [index, str(target)])


# 鼠标点击: 对准星位置的最近实体施放技能 1。
# 注意协议限制: onCastAbility 只接受 targetId, 没有位置参数, 因此若准星处
# 没有实体则无法施放(不能点地施法)。见 crosshair.gd 的说明。
func _cast_at_mouse(screen_pos: Vector2) -> void:
	if not _phase.is_in_world():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var world_pos := _camera.position + (screen_pos - viewport_size / 2.0) / _camera.zoom.x
	var best := _nearest_to(world_pos, CROSSHAIR_LOCK_RANGE)
	if best == 0:
		_hud.log("该处没有目标(协议不支持点地施法)")
		return
	_face_entity(best)
	_tcp.send_rpc(Protocol.RPC_CAST_ABILITY, { "index": 1, "targetId": best })
	_hud.log("施放技能 1 目标 %d" % best)


# 取距 origin 最近的其他实体(限定 max_range 内); 无则返回 0。
func _nearest_to(origin: Vector2, max_range: float) -> int:
	var best := 0
	var best_dist := max_range
	for entity: Entity in _world.other_entities():
		var node: ActorNode = _entity_view.get_node_for(entity.entity_id)
		if node == null:
			continue
		var dist: float = node.position.distance_to(origin)
		if dist < best_dist:
			best_dist = dist
			best = entity.entity_id
	return best


# 施法时转向目标(仅本地表现, 服务器会在下次移动时同步真实朝向)。
func _face_entity(target_id: int) -> void:
	var my_node: ActorNode = _entity_view.get_node_for(_world.self_id)
	var target_node: ActorNode = _entity_view.get_node_for(target_id)
	if my_node == null or target_node == null:
		return
	var to_target := target_node.position - my_node.position
	if to_target == Vector2.ZERO:
		return
	_last_heading = to_target
	_local_dir = Direction.angle_from_vector(to_target.x, to_target.y)
	_entity_view.set_self_facing(_local_dir, _moving)




func _process_auto_cast() -> void:
	if not auto_cast or _auto_cast_done:
		return
	var target := _nearest_to(_predictor.position, CAST_FALLBACK_RANGE)
	if target == 0:
		return
	_auto_cast_done = true
	_tcp.send_rpc(Protocol.RPC_CAST_ABILITY, { "index": 3, "targetId": target })
	_hud.log("自动施法 index=3 target=%d" % target)
