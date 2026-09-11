extends SceneTree
# 验证移动预测: 平滑性 + 发包频率 + 与服务端推演一致。
#
# 建模依据(见 server/game/cell/move.lua 的 Move:onTick):
#   * 服务器每 tick(0.1s)把队列里所有包按各自 dt 逐个推演, dt 截断到 0.2;
#   * 推演后 set("x"), 通过 prop 带 lastMoveSeq 回包;
#   * 客户端丢弃 seq <= serverSeq 的已发指令, 从权威位置重放剩余,
#     再加上"尚未发送的本地预测"(那部分服务器还不知道)。
#
# 判据:
#   A) 每帧位移**标准差** —— 手感是否平滑(理想 0)
#   B) **发包频率** —— 带宽是否可控(目标 ~10/s, 而非每帧 60/s)
#   C) 与服务端位置**偏差** —— 是否漂移(应小)
func _init():
	var SERVER_SPEED := 150.0
	var FRAME_DT := 1.0 / 60.0
	var TICK := 6            # 0.1s @60fps
	var RTT := 2
	var ok_all := true

	for case in [[SERVER_SPEED, true], [6.0, false]]:
		var client_speed: float = case[0]
		var expect_smooth: bool = case[1]

		var p := MovePredictor.new()
		p.set_speed(client_speed)
		p.reset_to(Vector2.ZERO)

		var server_x := 0.0
		var inbox: Array = []
		var queue: Array = []
		var steps: Array = []
		var prev := p.position.x
		var dir := Vector2.RIGHT
		var sent_dir := Vector2.ZERO
		var send_count := 0
		var frames := 60 * 5

		for frame in range(frames):
			# 方向变化 -> 立即冲刷(保证包内方向恒定)
			if dir != sent_dir:
				var c0 := p.take_command()
				if not c0.is_empty():
					queue.append(c0)
					send_count += 1
				sent_dir = dir
			# 本地推进每帧
			p.advance(dir, minf(FRAME_DT, Protocol.MOVE_DT_MAX))
			steps.append(p.position.x - prev)
			prev = p.position.x
			# 按间隔发包
			var unsent := p.unsent_dt()
			if unsent >= Protocol.MOVE_SEND_INTERVAL or unsent >= Protocol.MOVE_DT_MAX:
				var c1 := p.take_command()
				if not c1.is_empty():
					queue.append(c1)
					send_count += 1

			# 服务器每 tick 批量推演
			if frame % TICK == 0 and queue.size() > 0:
				var last := 0
				for c in queue:
					server_x += float(c["dx"]) * SERVER_SPEED * minf(float(c["dt"]), 0.2)
					last = int(c["seq"])
				queue.clear()
				inbox.append({ "x": server_x, "seq": last, "due": frame + RTT })

			# 回包 -> reconcile
			var keep: Array = []
			for r in inbox:
				if int(r["due"]) <= frame:
					var before_step := p.position.x
					# 该场景只沿 x 移动, 服务器只下发 x(增量下发语义)。
					p.reconcile(Vector2(float(r["x"]), 0.0), int(r["seq"]))
					var delta_corr := p.position.x - before_step
					if absf(delta_corr) > 0.5:
						steps[steps.size() - 1] = delta_corr
				else:
					keep.append(r)
			inbox = keep

		var sample: Array = []
		for i in range(30, steps.size()):
			sample.append(float(steps[i]))
		var mean := 0.0
		for s in sample:
			mean += s
		mean /= sample.size()
		var vs := 0.0
		for s in sample:
			vs += (s - mean) * (s - mean)
		var sd := sqrt(vs / sample.size())
		var drift := absf(p.position.x - server_x)
		var rate := float(send_count) / (float(frames) * FRAME_DT)

		var smooth := sd < 0.15
		var rate_ok := rate <= 12.0        # 目标 ~10/s
		if smooth != expect_smooth:
			ok_all = false
		print("TEST: 速度=%-6.1f -> 每帧位移 均值=%.3f 标准差=%.3f | 发包=%.1f/s | 偏差=%.2f | %s" % [
			client_speed, mean, sd, rate, drift,
			("平滑" if smooth else "有顿挫")])
		if not rate_ok and expect_smooth:
			ok_all = false
			print("TEST:   !! 发包频率 %.1f/s 超出目标(应~10/s)" % rate)

	print("TEST: " + ("ALL OK" if ok_all else "FAIL"))
	quit(0 if ok_all else 1)
