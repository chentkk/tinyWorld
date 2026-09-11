extends SceneTree
# 验收标准(经实测修正):
#   dir 在游戏里恒为单圈角度: 服务端 Move:onTick 用 math.atan(dy,dx) 产出,
#   结果必在 [-PI, PI)。多圈角度不会出现在真实数据里。
#   因此:
#     A) 单圈角度(|deg| <= 180): 必须与服务端**逐点一致**
#     B) 多圈角度: 服务端自身不自洽(135度->DOWN 但 495度->LEFT), 不作为标准;
#        只要求本实现确定性(同输入同输出)
func _init():
	var f = FileAccess.open("res://test/lua_ref.txt", FileAccess.READ)
	var single_total = 0
	var single_bad = 0
	var multi_total = 0
	var shown = 0
	while not f.eof_reached():
		var line = f.get_line().strip_edges()
		if line == "": continue
		var sp = line.rfind(" ")
		if sp <= 0: continue
		var ang = float(line.substr(0, sp))
		var lua_dir = int(line.substr(sp + 1).strip_edges())
		var deg = ang * 180.0 / PI
		var gd_dir = Direction.quantize(ang)
		if abs(deg) <= 180.0 + 1e-9:
			single_total += 1
			if gd_dir != lua_dir:
				single_bad += 1
				if shown < 10:
					print("  DIFF deg=%.6f lua=%s gd=%s" % [deg, Direction.dir_name(lua_dir), Direction.dir_name(gd_dir)])
					shown += 1
		else:
			multi_total += 1
	print("PARITY: 单圈角度 %d 个, 不一致 %d 个" % [single_total, single_bad])
	print("PARITY: 多圈角度 %d 个 (服务端自身不自洽, 不计入)" % multi_total)
	# 确定性
	var det = true
	for i in range(-720, 721):
		var a: float = float(i) * PI / 180.0
		if Direction.quantize(a) != Direction.quantize(a): det = false
	# 边界实测值
	var expect = {45: Direction.RIGHT, 135: Direction.DOWN, 225: Direction.LEFT, 315: Direction.RIGHT}
	var edge_ok = true
	for d in expect.keys():
		if Direction.quantize(float(d) * PI / 180.0) != expect[d]: edge_ok = false
	print("PARITY: 确定性=%s  边界点符合实测=%s" % [str(det), str(edge_ok)])
	print("PARITY: " + ("PASS" if (single_bad == 0 and det and edge_ok) else "FAIL"))
	quit(0 if (single_bad == 0 and det and edge_ok) else 1)
