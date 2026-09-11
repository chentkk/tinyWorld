extends SceneTree
# 验证"进入游戏完成"的判定(WorldReady)。
#
# 背景: 服务端初始快照**没有**"发完了"的标志, 且实测下发顺序是:
#   object add(isSelf) -> record -> view bag/equipment -> selectCharacter
#   -> view modifiers_view/abilities_view(更晚)
# 因此必须等"必需数据清单"齐全才算可玩。
#
# 关键陷阱(本测试覆盖): **空表/空容器是合法状态**。
#   玩家还没接任务时 current_tasks 为空, 空背包时 bag 无子对象 ——
#   这些都不代表"数据没到"。必须区分"已收到但为空"与"从未收到",
#   否则会永远等不到就绪(实测曾误报 record:current_tasks 缺失)。
func _init():
	var ok_all := true
	var world := WorldState.new()
	var gate := WorldReady.new(world)

	# --- 初始: 什么都还没到 -> 不应就绪 ---
	var missing0 := gate.pending_items()
	var not_ready := not gate.is_ready() and missing0.size() > 0
	if not not_ready:
		ok_all = false
	print("TEST: 初始状态 缺失 %d 项, 就绪=%s  %s" % [
		missing0.size(), str(gate.is_ready()), "OK" if not_ready else "FAIL"])

	# --- 收到 self, 但视图还没到 -> 仍不就绪 ---
	world.apply_message({ "t": "object", "n": "add", "d": {
		"entityId": 7, "kind": "Player", "isSelf": true, "props": { "x": 0, "y": 0 } } })
	var still_missing := gate.pending_items()
	gate.poll(0.0)
	var partial := not gate.is_ready() and still_missing.size() == 4
	if not partial:
		ok_all = false
	print("TEST: 仅 self 到位 缺失 %d 项(应 4), 就绪=%s  %s" % [
		still_missing.size(), str(gate.is_ready()), "OK" if partial else "FAIL"])

	# --- 收到**空** record 与**空** view -> 应视为已到位(关键断言) ---
	world.apply_message({ "t": "record", "n": "current_tasks",
		"d": { "entityId": 7, "ops": [] } })
	for vname in ["bag", "equipment", "abilities_view"]:
		world.apply_message({ "t": "view", "n": vname,
			"d": { "entityId": 7, "ops": [] } })
	var missing_after := gate.pending_items()
	var empty_ok := missing_after.is_empty()
	if not empty_ok:
		ok_all = false
	print("TEST: 空表/空容器到位后 缺失 %d 项(应 0)  %s" % [
		missing_after.size(), "OK" if empty_ok else "FAIL"])

	# --- poll 后应判定就绪 ---
	gate.poll(0.0)
	var ready_ok := gate.is_ready()
	if not ready_ok:
		ok_all = false
	print("TEST: poll 后 就绪=%s  %s" % [str(gate.is_ready()), "OK" if ready_ok else "FAIL"])

	# --- 超时兜底: 缺数据时也能带警告放行, 不会永久卡住 ---
	var w2 := WorldState.new()
	var g2 := WorldReady.new(w2)
	g2.poll(WorldReady.TIMEOUT + 0.1)
	var timeout_ok := g2.is_ready()
	if not timeout_ok:
		ok_all = false
	print("TEST: 超时兜底 就绪=%s (应 true, 避免永久卡加载)  %s" % [
		str(g2.is_ready()), "OK" if timeout_ok else "FAIL"])

	print("TEST: " + ("ALL OK" if ok_all else "FAIL"))
	quit(0 if ok_all else 1)
