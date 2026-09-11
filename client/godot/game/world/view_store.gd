# view_store.gd — view(容器/视图)同步的本地维护。
# 服务器下发增量 op: add / remove / set(子对象) / view(容器自身属性)。
extends RefCounted
class_name ViewStore

# entityId -> { viewName -> { props: {}, children: { id -> Dictionary } } }
var _by_entity: Dictionary = {}


func apply(view_name: String, d: Dictionary) -> void:
	var entity_id := int(d.get("entityId", 0))
	var by_name: Dictionary = _by_entity.get(entity_id, {})
	var view: Dictionary = by_name.get(view_name, _empty_view())

	for op in d.get("ops", []):
		var otype := str(op.get("type", ""))
		var data: Dictionary = op.get("data", {})
		match otype:
			"add":
				view["children"][op.get("id", 0)] = data.duplicate()
			"remove":
				view["children"].erase(op.get("id", 0))
			"set":
				var cid: Variant = op.get("id", 0)
				var child: Dictionary = view["children"].get(cid, {})
				for k in data.keys():
					child[k] = data[k]
				view["children"][cid] = child
			"view":
				# 容器自身属性变化(无 id)。
				for k in data.keys():
					view["props"][k] = data[k]

	by_name[view_name] = view
	_by_entity[entity_id] = by_name


# 返回 { props, children }; 无数据时返回空视图结构。
# 命名避开 Object.get(), 否则会与原生方法签名冲突。
func get_view(entity_id: int, view_name: String) -> Dictionary:
	var by_name: Dictionary = _by_entity.get(entity_id, {})
	return by_name.get(view_name, _empty_view())


# 该视图是否已收到过数据。
# 用于"就绪判定": 空背包是合法的(children 为空), 但**从未收到**该视图
# 说明初始快照还没发完 —— 二者必须区分, 故不能只看 children 是否为空。
func has_view(entity_id: int, view_name: String) -> bool:
	var by_name: Dictionary = _by_entity.get(entity_id, {})
	return by_name.has(view_name)


# 便利方法: 只取子对象数组。
func children_of(entity_id: int, view_name: String) -> Array:
	var view := get_view(entity_id, view_name)
	var out: Array = []
	for k in view["children"].keys():
		out.append(view["children"][k])
	return out


func clear() -> void:
	_by_entity = {}


func _empty_view() -> Dictionary:
	return { "props": {}, "children": {} }
