extends SceneTree
# 回归: 停止移动时不应清空"已发送但未确认"的指令, 也不应发 onStopMove。
#
# 背景(A/B 实测定位的 bug):
#   服务端的 onStopMove 是**无条件清空队列**(server/game/cell/move.lua):
#       function Move:onStopMove(d) self.queue = {} end
#   客户端"松手"时会 flush 一个移动包再立刻发 onStopMove —— 二者若落在同一
#   tick 内, 那个移动包会被 onStopMove 一起清掉。服务端从未推演该位移, 而客户端
#   已本地预测走过, 于是下次 reconcile 把客户端**往回拉**。
#   实测(走走停停 6 秒):
#       发 onStopMove   -> 6 次大校正, 累计 74.5 单位, 最大 12.5
#       不发 onStopMove -> 0 次, 0.0, 0.0
#
# 另: clear_pending() 不能清 _pending(那些指令已发出, 服务器可能还没处理完),
#     只清"尚未发送"的累积量 —— 否则同样造成回拉。
func _init():
	var ok_all := true

	# --- 断言 1: 按 main.gd 的真实停止序列, pending 必须保留 ---
	# main.gd 停止顺序: _flush_move() -> clear_pending() -> (不发 onStopMove)
	var p := MovePredictor.new()
	p.set_speed(150.0)
	p.reset_to(Vector2(1000, 1000))
	p.advance(Vector2(1, 0), 0.05)         # 累积 0.05, 未发送
	p.advance(Vector2(1, 0), 0.05)         # 累积到 0.1
	# 模拟停止: 先 flush(打包发送), 再 clear_pending
	var flushed := p.take_command()
	if not flushed.is_empty():
		pass
	p.clear_pending()
	var pending_after := p._pending.size()
	var unsent_after := p.unsent_dt()
	var kept := pending_after == 1 and unsent_after == 0.0
	if not kept:
		ok_all = false
	print("TEST: 停止序列后: 已发送 pending=%d(应 1), 未发送=%.3f(应 0)  %s" % [
		pending_after, unsent_after, "OK" if kept else "FAIL"])

	# --- 断言 2: 服务器尚未处理该指令时, reconcile 不应回拉 ---
	# 服务器位置还停在 1000(未处理), 客户端重放 pending 后应保持原位。
	var before := p.position
	p.reconcile(Vector2(1000, 1000), 0)
	var corr := (p.position - before).length()
	var no_pull := corr < 0.01
	if not no_pull:
		ok_all = false
	print("TEST: reconcile(服务器未处理该指令) 位置变化=%.4f (应≈0)  %s" % [
		corr, "OK" if no_pull else "FAIL"])

	# --- 断言 3: 反例 —— 清空 pending 就会被拉回(旧行为) ---
	var p2 := MovePredictor.new()
	p2.set_speed(150.0)
	p2.reset_to(Vector2(1000, 1000))
	p2.advance(Vector2(1, 0), 0.1)
	p2.take_command()
	p2._pending.clear()                    # 旧的错误行为
	var before2 := p2.position
	p2.reconcile(Vector2(1000, 1000), 0)
	var pulled := before2.x - p2.position.x
	print("TEST: [反例] 清空 pending 后被拉回 %.1f 单位(证明该保护必要)" % pulled)
	if pulled < 5.0:
		ok_all = false
		print("TEST:   反例未复现回拉, 测试无效")

	print("TEST: " + ("ALL OK" if ok_all else "FAIL"))
	quit(0 if ok_all else 1)
