# actor_def.gd — 对象(实体)表现定义与查表。
#
# 为什么是配置驱动:
#   实体的"表现"随 kind 而变(玩家有名字/序列帧, 投掷物是小圆点, NPC 可能带血条)。
#   若把这些差异写进 ActorNode 的 if/else, 每加一种 kind 都要改代码。
#   改为读配置后, 新增 NPC/投掷物只需在 assets/config/actor_defs.json 加一项。
#
# 配置字段:
#   sprite             序列帧描述文件路径; 空或缺省则用占位图形
#   show_name          是否显示名字标签
#   interpolate        位置更新是否插值(他人实体用; 投掷物通常也需要)
#   z_index            绘制层级
#   placeholder_radius 占位图形半径(无美术时)
#   placeholder_color  占位图形颜色 [r,g,b]
extends RefCounted
class_name ActorDef

const CONFIG_PATH := "res://assets/config/actor_defs.json"

# 默认值: 配置缺失或字段未提供时使用。
const FALLBACK := {
	"sprite": "",
	"show_name": true,
	"interpolate": true,
	"z_index": 10,
	"placeholder_radius": 8.0,
	"placeholder_color": Color(1.0, 0.45, 0.2),
}

static var _defaults: Dictionary = {}
static var _kinds: Dictionary = {}
static var _loaded := false


# 取某 kind 的定义(返回副本, 调用方可自由读取)。
static func get_def(kind: String) -> Dictionary:
	_ensure_loaded()
	var def: Dictionary = _defaults.duplicate()
	var overrides: Dictionary = _kinds.get(kind, {})
	for k in overrides.keys():
		def[k] = overrides[k]
	return def


# 是否配置了可用美术(有 sprite 字段)。
static func has_sprite(def: Dictionary) -> bool:
	return not str(def.get("sprite", "")).is_empty()


# 重新加载配置(测试/热更用)。
static func reload() -> void:
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_defaults = FALLBACK.duplicate()
	_kinds = {}

	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("[ActorDef] 配置不存在, 全部使用默认值: %s" % CONFIG_PATH)
		return

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[ActorDef] 配置解析失败, 全部使用默认值: %s" % CONFIG_PATH)
		return

	var raw_default: Variant = parsed.get("default", null)
	if typeof(raw_default) == TYPE_DICTIONARY:
		for k in raw_default.keys():
			_defaults[k] = _normalize(k, raw_default[k])

	var raw_kinds: Variant = parsed.get("kinds", null)
	if typeof(raw_kinds) == TYPE_DICTIONARY:
		for kind in raw_kinds.keys():
			var entry: Dictionary = {}
			for k in raw_kinds[kind].keys():
				entry[k] = _normalize(k, raw_kinds[kind][k])
			_kinds[str(kind)] = entry


# 把 JSON 里的原始值转成运行期类型(颜色数组 -> Color 等)。
static func _normalize(key: String, value: Variant) -> Variant:
	if key == "placeholder_color" and typeof(value) == TYPE_ARRAY and value.size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]))
	return value
