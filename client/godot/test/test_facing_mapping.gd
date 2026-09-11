extends SceneTree
# 端到端: 验证客户端把服务端 dir 正确映射到 4 向美术行
func _init():
	# 服务端实测的 4 个方向代表角度
	var cases = [
		[0.0, "RIGHT", "right"],
		[PI/2, "DOWN", "down"],
		[PI, "LEFT", "left"],
		[-PI/2, "UP", "up"],
		[PI/4, "RIGHT", "right"],     # 45度边界 -> RIGHT(实测)
		[-PI/4, "RIGHT", "right"],    # -45度 -> RIGHT
		[3*PI/4, "DOWN", "down"],
		[-3*PI/4, "LEFT", "left"],
	]
	var ok = true
	var dirs4 = ["down", "up", "left", "right"]   # 4行布局
	var dirs3 = ["down", "up", "side"]            # 3行布局(含镜像)
	for c in cases:
		var rad = c[0]
		var dir = Direction.quantize(rad)
		var name = Direction.dir_name(dir)
		var pick4 = Facing.render_for(dir, dirs4)
		var pick3 = Facing.render_for(dir, dirs3)
		var pass_ = (name == c[1] and str(pick4.get("row","")) == c[2])
		if not pass_: ok = false
		print("VERIFY %-8s rad=%+.4f -> %-5s | 4行=%-5s flip=%-5s | 3行=%-5s flip=%s  %s" % [
			str(rad), rad, name, str(pick4.get("row","")), str(pick4.get("flip",false)),
			str(pick3.get("row","")), str(pick3.get("flip",false)),
			"OK" if pass_ else "BAD"])
	print("VERIFY: " + ("ALL OK" if ok else "HAS FAIL"))
	quit(0 if ok else 1)
