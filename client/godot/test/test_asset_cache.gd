extends SceneTree
# 验证资源缓存与引用计数(AssetCache)。
#
# 目的: 同一份序列帧被多个实体共用时只构建一次; 实体销毁时按引用计数释放,
# 避免资源泄漏或误释放(还有人在用就被清掉)。
func _init():
	var ok_all := true
	AssetCache.clear()
	var path := "res://assets/sprites/hero.json"

	# --- 1) 首次申请: 建立缓存, 计数 1 ---
	var f1 := AssetCache.acquire_frames(path)
	var first := f1 != null and AssetCache.ref_count(path) == 1
	if not first:
		ok_all = false
	print("TEST: 首次申请 成功=%s 引用=%d(应 1)  %s" % [
		str(f1 != null), AssetCache.ref_count(path), "OK" if first else "FAIL"])

	# --- 2) 再次申请: 复用同一份, 计数 2 ---
	var f2 := AssetCache.acquire_frames(path)
	var reuse := f2 == f1 and AssetCache.ref_count(path) == 2
	if not reuse:
		ok_all = false
	print("TEST: 再次申请 复用同一对象=%s 引用=%d(应 2)  %s" % [
		str(f2 == f1), AssetCache.ref_count(path), "OK" if reuse else "FAIL"])

	# --- 3) 释放一次: 仍被引用, 不应移出缓存 ---
	AssetCache.release(path)
	var kept := AssetCache.ref_count(path) == 1
	if not kept:
		ok_all = false
	print("TEST: 释放一次 引用=%d(应 1, 仍缓存)  %s" % [
		AssetCache.ref_count(path), "OK" if kept else "FAIL"])

	# --- 4) 再释放: 计数归零, 移出缓存 ---
	AssetCache.release(path)
	var evicted := AssetCache.ref_count(path) == 0
	if not evicted:
		ok_all = false
	print("TEST: 再次释放 引用=%d(应 0, 已移出)  %s" % [
		AssetCache.ref_count(path), "OK" if evicted else "FAIL"])

	# --- 5) 多余的 release 不应出错(容错) ---
	AssetCache.release(path)
	AssetCache.release("res://not/exist.json")
	var tolerant := AssetCache.ref_count(path) == 0
	if not tolerant:
		ok_all = false
	print("TEST: 多余 release 不崩溃  %s" % ("OK" if tolerant else "FAIL"))

	# --- 6) 不存在的文件返回 null, 不污染缓存 ---
	var bad := AssetCache.acquire_frames("res://assets/sprites/__nope__.json")
	var bad_ok := bad == null and AssetCache.cached_count() == 0
	if not bad_ok:
		ok_all = false
	print("TEST: 缺失文件 返回 null=%s 缓存数=%d(应 0)  %s" % [
		str(bad == null), AssetCache.cached_count(), "OK" if bad_ok else "FAIL"])

	AssetCache.clear()
	print("TEST: " + ("ALL OK" if ok_all else "FAIL"))
	quit(0 if ok_all else 1)
