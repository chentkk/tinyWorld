# record_store.gd — record(表格)同步的本地维护。
# 服务器下发增量 op: add / remove / set。
extends RefCounted
class_name RecordStore

# entityId -> { recordName -> { key -> row(Dictionary) } }
var _by_entity: Dictionary = {}


func apply(record_name: String, d: Dictionary) -> void:
	var entity_id := int(d.get("entityId", 0))
	var by_name: Dictionary = _by_entity.get(entity_id, {})
	var rec: Dictionary = by_name.get(record_name, {})

	for op in d.get("ops", []):
		var otype := str(op.get("type", ""))
		var key := str(op.get("key", ""))
		match otype:
			"add":
				rec[key] = (op.get("data", {}) as Dictionary).duplicate()
			"remove":
				rec.erase(key)
			"set":
				# 增量合并到已有行; 行不存在时也建一行(容错于乱序到达)。
				var row: Dictionary = rec.get(key, {})
				for k in (op.get("data", {}) as Dictionary).keys():
					row[k] = op["data"][k]
				rec[key] = row

	by_name[record_name] = rec
	_by_entity[entity_id] = by_name


# 返回 { key -> row }; 无数据时返回空字典。
# 命名避开 Object.get(), 否则会与原生方法签名冲突。
func get_rows(entity_id: int, record_name: String) -> Dictionary:
	var by_name: Dictionary = _by_entity.get(entity_id, {})
	return by_name.get(record_name, {})


# 该表是否已收到过同步。
# 用于"就绪判定": **空表是合法的**(玩家还没接任务, 或任务已全部完成),
# 但"从未收到"说明初始快照还没发完 —— 二者必须区分, 故不能只看行数。
func has_record(entity_id: int, record_name: String) -> bool:
	var by_name: Dictionary = _by_entity.get(entity_id, {})
	return by_name.has(record_name)


func clear() -> void:
	_by_entity = {}
