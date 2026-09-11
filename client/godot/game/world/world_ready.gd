# world_ready.gd — "进入游戏完成"的判定。
#
# 问题:
#   进入世界时服务端会连发多条消息(object add / record / view ...), 但
#   **没有一条能表示"初始数据已发完"**。实测下发顺序:
#       object add(isSelf)
#       record current_tasks
#       view bag / equipment
#       ACCOUNT selectCharacter{code=0}   <- 文档说这是最后一步
#       view modifiers_view / abilities_view   <- 实际在这之后才到!
#   若客户端一收到 object add 就放开所有游戏逻辑, 背包/技能面板会短暂为空,
#   依赖这些数据的模块(如施法、装备)会读到不完整状态。
#
# 方案(两层):
#   1) **服务器显式就绪消息**(最可靠, 见下方 READY_MSG)。服务端在初始快照
#      全部发完后补发一条, 客户端收到即视为就绪。这是建议服务端新增的协议。
#   2) **必需数据清单**(兜底, 服务端未改时也能正确工作): 逐项检查本地的
#      必需数据是否到位, 全部到位才判定就绪。
#   两者取"先到者": 收到显式就绪消息, 或清单全部满足, 都算就绪。
#
# 超时: 若清单长期不满足(如服务端未下发某个视图), 达到超时后**带警告放行**,
#       避免玩家永远卡在加载界面。放行时会打印缺失项, 便于定位。
extends RefCounted
class_name WorldReady

signal became_ready(missing: Array)

# 服务端显式就绪消息(建议新增的协议)。
# 服务端应在"初始快照全部发完"后补发:
#   { "t": "ACCOUNT", "n": "enterWorldComplete", "d": { "playerId": 1 } }
const READY_MSG_TYPE := "ACCOUNT"
const READY_MSG_NAME := "enterWorldComplete"

# 超时(秒): 清单迟迟不满足时带警告放行, 避免永久卡加载。
const TIMEOUT := 5.0

# 必需数据清单。每项为一个"检查项"字典:
#   kind: "self" | "record" | "view"
#   name: record/view 名(仅后两者需要)
# 说明: 这些是"开始游戏所必需"的最小集合 —— 玩家自己要能看到(背包/装备/
# 技能), 任务表用于任务面板。新增必需的视图时在此追加即可。
const REQUIRED := [
	{ "kind": "self" },
	{ "kind": "record", "name": "current_tasks" },
	{ "kind": "view", "name": "bag" },
	{ "kind": "view", "name": "equipment" },
	{ "kind": "view", "name": "abilities_view" },
]

var _world: WorldState
var _is_ready := false
var _elapsed := 0.0
# 上一帧尚未满足的清单项(去重打印用)。
var _last_missing: Array = []


func _init(world: WorldState) -> void:
	_world = world


func is_ready() -> bool:
	return _is_ready


# 每帧调用: 推进超时并在满足时判定就绪。
func poll(delta: float) -> void:
	if _is_ready:
		return
	_elapsed += delta

	var missing := pending_items()
	if missing.is_empty():
		_mark_ready([])
		return

	# 打印一次缺失详情, 便于联调(避免每帧刷屏)。
	if missing != _last_missing:
		_last_missing = missing
		push_warning("[WorldReady] 等待初始数据: %s" % str(missing))

	if _elapsed >= TIMEOUT:
		push_warning("[WorldReady] 超时 %.1fs, 带警告放行; 缺失: %s" % [_elapsed, str(missing)])
		_mark_ready(missing)


# 收到服务端显式就绪消息时调用。
func on_ready_message() -> void:
	if _is_ready:
		return
	_mark_ready(pending_items())


# 收集尚未满足的清单项(空数组 = 全部就绪)。
func pending_items() -> Array:
	var missing: Array = []
	for item in REQUIRED:
		var kind := str(item["kind"])
		match kind:
			"self":
				if _world.get_self() == null:
					missing.append("self")
			"record":
				var rname := str(item["name"])
				# 用 has_record 而非"行数非空": 空表是合法状态(还没接任务),
				# 只有"从未收到"才算未就绪。
				if not _world.records.has_record(_world.self_id, rname):
					missing.append("record:" + rname)
			"view":
				var vname := str(item["name"])
				# 视图到位与否看它是否已建立(children 可以为空 —— 空背包是合法的)。
				if not _world.views.has_view(_world.self_id, vname):
					missing.append("view:" + vname)
	return missing


# 断线/重登时重置。
func reset() -> void:
	_is_ready = false
	_elapsed = 0.0
	_last_missing = []


func _mark_ready(missing: Array) -> void:
	_is_ready = true
	became_ready.emit(missing)
