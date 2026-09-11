extends SceneTree
# 回归: reconcile 不得**重复累加**未确认指令, 也不得扰动未下发的分量。
#
# 背景(实测定位的 bug):
#   旧实现从 position 取"未下发分量"作基准: base.x = position.x, 然后又在 base
#   之上重放 pending。但 position 里**已经包含**了 pending 的位移 —— 于是重放
#   等于再加一遍, 未下发的分量凭空被校正。
#   实测(快速交替 A/W, 服务器增量下发):
#       [ZZ] 校正=(-15.52, 0.00) auth={x:false, y:true}   <- x 未下发却动了 15.5
#       [ZZ] 校正=(15.53, -11.18) auth={x:true, y:false}
#   现象: 快速转向时画面抽动、摄像机晃动。
#
# 正确模型(标准 Reconciliation):
#   position = server_pos + Σ(未确认指令位移) + 未发送位移
#   **重算** position, 而非在旧 position 上增量修改(旧值里已含 pending 的位移)。
#
# server_pos 直接取自 Entity.props 的 (x, y)。服务端虽然只下发变化字段,
# 但客户端 props 是增量**合并**的(未变分量保留旧值), 因此它天然就是
# "服务器最新坐标" —— 这也是场景 3 里 client_props 所模拟的行为。
func _init():
	var ok_all := true

	# --- 场景 1: 位置必须**从 server_pos 重算**, 不得在旧 position 上叠加 ---
	# 若实现写成"base = position; pos = base + 重放 pending", 就会重复累加,
	# 结果比 server_pos + 重放 多出一份 pending 的位移。这里直接断言最终值。
	var p := MovePredictor.new()
	p.set_speed(150.0)
	p.reset_to(Vector2(1000, 1000))
	p.advance(Vector2(-1, 0), 0.1)     # 向左 15 -> position=(985,1000)
	p.take_command()                   # 发出 seq=1, 进入 pending(未确认)
	var expect := Vector2(985.0, 1000.0)   # server_pos(1000,1000) + 重放 15
	p.reconcile(Vector2(1000, 1000), 0)
	var err := (p.position - expect).length()
	var exact := err < 0.01
	if not exact:
		ok_all = false
	print("TEST: 位置从 server_pos 重算: 得到 %s, 期望 %s, 误差=%.4f  %s" % [
		str(p.position), str(expect), err, "OK" if exact else "FAIL"])

	# --- 场景 2: 服务器确认后, 该指令应被丢弃且位置不漂移 ---
	var p2 := MovePredictor.new()
	p2.set_speed(150.0)
	p2.reset_to(Vector2(1000, 1000))
	p2.advance(Vector2(1, 0), 0.1)     # +15
	p2.take_command()                  # seq=1, pending
	var after_advance := p2.position
	# 服务器确认 seq=1, 且其位置已包含该位移
	p2.reconcile(Vector2(after_advance.x, 1000), 1)
	var drift := absf(p2.position.x - after_advance.x)
	var single_count := drift < 0.01
	if not single_count:
		ok_all = false
	print("TEST: 服务器确认后 位置漂移=%.4f (应≈0, pending 只计一次)  %s" % [
		drift, "OK" if single_count else "FAIL"])

	# --- 场景 3: 快速交替方向(复现原 bug 的路径) ---
	# 严格按 main.gd 的时序建模:
	#   * 方向变化 -> 先 flush(把上一方向的累积量打包发出)
	#   * 每帧 advance(本地预测)
	#   * 累积到间隔 -> flush
	#   * 服务器每 6 帧推演一次, 且只下发变化的分量
	var p3 := MovePredictor.new()
	p3.set_speed(150.0)
	p3.reset_to(Vector2(1000, 1000))
	var max_bad := 0.0
	var srv := Vector2(1000, 1000)
	# 模拟客户端 Entity.props: 增量合并, 未下发分量保留旧值。
	var client_props := Vector2(1000, 1000)
	var inbox: Array = []
	var queue: Array = []
	var dir := Vector2(-1, 0)
	var last_dir := Vector2.ZERO
	for frame in range(180):
		# 每 8 帧切换方向(模拟快速点按 A/W)
		if frame % 8 == 0:
			dir = Vector2(-1, 0) if (frame / 8) % 2 == 0 else Vector2(0, -1)
		# 方向变化 -> 立即 flush(与 _push_move 一致)
		if dir != last_dir:
			var c0 := p3.take_command()
			if not c0.is_empty():
				queue.append(c0)
			last_dir = dir
		var dt := 1.0 / 60.0
		p3.advance(dir, dt)
		var u := p3.unsent_dt()
		if u >= Protocol.MOVE_SEND_INTERVAL or u >= Protocol.MOVE_DT_MAX:
			var c := p3.take_command()
			if not c.is_empty():
				queue.append(c)
		# 服务器每 6 帧推演一次
		if frame % 6 == 0 and queue.size() > 0:
			var old := srv
			var last := 0
			for c in queue:
				srv += Vector2(float(c["dx"]), float(c["dy"])) * 150.0 * minf(float(c["dt"]), 0.2)
				last = int(c["seq"])
			queue.clear()
			# 服务端只下发**变化的分量**(增量下发)
			var ch := {}
			if not is_equal_approx(srv.x, old.x):
				ch["x"] = srv.x
			if not is_equal_approx(srv.y, old.y):
				ch["y"] = srv.y
			inbox.append({ "ch": ch, "seq": last, "due": frame + 2 })
		var keep: Array = []
		for r in inbox:
			if int(r["due"]) <= frame:
				var b: Vector2 = p3.position
				# 客户端 props 是增量**合并**的: 未下发的分量保留上次值。
				# 这正是 entity.position() 在真实客户端里的行为。
				var ch: Dictionary = r["ch"]
				if ch.has("x"):
					client_props.x = float(ch["x"])
				if ch.has("y"):
					client_props.y = float(ch["y"])
				p3.reconcile(client_props, int(r["seq"]))
				max_bad = maxf(max_bad, (p3.position - b).length())
			else:
				keep.append(r)
		inbox = keep
	# 校正量应接近 0(仅剩 RTT 内未确认的正常量, 远小于一次方向位移)
	var zigzag_ok := max_bad < 8.0
	if not zigzag_ok:
		ok_all = false
	print("TEST: 快速交替方向 最大单次校正=%.2f 单位 (阈值 8)  %s" % [
		max_bad, "OK" if zigzag_ok else "FAIL"])

	print("TEST: " + ("ALL OK" if ok_all else "FAIL"))
	quit(0 if ok_all else 1)
