extends SceneTree
# 验证 batch 信封展开(doc/protocol.md 2.2)。
# 服务器每 tick 把发给同一玩家的多条消息合并成一帧; 客户端需按顺序展开。
func _init():
	var tcp := TcpClient.new()
	var got: Array = []
	tcp.message.connect(func(m: Dictionary) -> void:
		got.append("%s/%s" % [str(m.get("t","")), str(m.get("n",""))]))

	# 1) 普通消息应原样透传
	tcp._emit_expanded({ "t": "prop", "n": "props", "d": { "entityId": 1 } })
	# 2) batch 内含多条, 顺序必须保持
	tcp._emit_expanded({ "t": "batch", "n": "msgs", "d": { "msgs": [
		{ "t": "prop", "n": "props", "d": { "entityId": 1, "x": 10 } },
		{ "t": "record", "n": "current_tasks", "d": { "entityId": 1, "ops": [] } },
		{ "t": "view", "n": "bag", "d": { "entityId": 1, "ops": [] } },
		{ "t": "RPC", "n": "onCombatDamage", "d": { "entityId": 1, "amount": 5 } },
	] } })
	# 3) 空 batch 不应产生消息
	tcp._emit_expanded({ "t": "batch", "n": "msgs", "d": { "msgs": [] } })
	# 4) 缺字段的 batch 不应崩溃
	tcp._emit_expanded({ "t": "batch", "n": "msgs", "d": {} })

	var expect := [
		"prop/props",
		"prop/props", "record/current_tasks", "view/bag", "RPC/onCombatDamage",
	]
	var ok := got.size() == expect.size()
	for i in range(mini(got.size(), expect.size())):
		if got[i] != expect[i]:
			ok = false
	print("TEST: 收到 %d 条: %s" % [got.size(), str(got)])
	print("TEST: 期望 %d 条: %s" % [expect.size(), str(expect)])
	print("TEST: 顺序与数量" , ("OK" if ok else "FAIL"))
	print("TEST: " + ("ALL OK" if ok else "FAIL"))
	quit(0 if ok else 1)
