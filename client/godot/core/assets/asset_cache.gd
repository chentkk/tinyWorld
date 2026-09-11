# asset_cache.gd — 资源缓存与生命周期。
#
# 为什么需要:
#   同一份序列帧会被多个实体共用(10 个玩家共用一张 hero 表)。若每个实体各自
#   load() 一次, 会重复解码贴图、重复构建 SpriteFrames。
#   同时, 退出世界/换地图时需要能**统一释放**, 避免长时间游玩后显存堆积。
#
# 设计:
#   * 按 key 缓存 SpriteFrames(同一描述文件只构建一次);
#   * 引用计数: acquire/release 成对使用, 计数归零才真正释放;
#   * 支持按"标签"批量释放(如卸地图时释放该地图的所有资源)。
#
# 用法:
#   var frames := AssetCache.acquire_frames("res://assets/sprites/hero.json")
#   ...
#   AssetCache.release("res://assets/sprites/hero.json")
extends RefCounted
class_name AssetCache

# key -> { value: Variant, refs: int }
static var _entries: Dictionary = {}


# 取序列帧(SpriteFrames); 已缓存则直接返回并增加引用计数。
# 加载失败返回 null(调用方自行回退到占位绘制)。
static func acquire_frames(desc_path: String) -> SpriteFrames:
	if desc_path.is_empty():
		return null

	var entry: Dictionary = _entries.get(desc_path, {})
	if not entry.is_empty():
		entry["refs"] = int(entry["refs"]) + 1
		return entry["value"]

	var frames := SpriteSheet.load_frames(desc_path)
	if frames == null:
		return null

	_entries[desc_path] = { "value": frames, "refs": 1 }
	return frames


# 释放一次引用; 计数归零时移出缓存。
static func release(desc_path: String) -> void:
	var entry: Dictionary = _entries.get(desc_path, {})
	if entry.is_empty():
		return
	entry["refs"] = int(entry["refs"]) - 1
	if int(entry["refs"]) <= 0:
		_entries.erase(desc_path)


# 清空全部缓存(退出世界 / 断线时调用)。
static func clear() -> void:
	_entries.clear()


# 当前缓存的资源数(调试/测试用)。
static func cached_count() -> int:
	return _entries.size()


# 某个资源当前的引用计数(测试用); 未缓存返回 0。
static func ref_count(desc_path: String) -> int:
	var entry: Dictionary = _entries.get(desc_path, {})
	return int(entry.get("refs", 0))
