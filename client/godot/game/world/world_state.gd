# world_state.gd — 进入世界后的全部本地状态。
# 消费 object / prop / record / view 四类同步消息, 维护实体表与表格/视图,
# 并通过信号通知 ui 层刷新。不含任何渲染逻辑。
extends RefCounted
class_name WorldState

signal entity_added(entity: Entity)
signal entity_removed(entity_id: int)
signal props_changed(entity: Entity, changed: Dictionary)
signal record_changed(entity_id: int, record_name: String, ops: Array)
signal view_changed(entity_id: int, view_name: String, ops: Array)
signal cleared

var entities: Dictionary = {}     # entityId -> Entity
var records: RecordStore
var views: ViewStore
var self_id: int = 0


func _init() -> void:
	records = RecordStore.new()
	views = ViewStore.new()


# 统一的同步消息入口(msg 为 {t, n, d})。
func apply_message(msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	var n := str(msg.get("n", ""))
	var d: Dictionary = msg.get("d", {})
	match t:
		Protocol.T_OBJECT:
			if n == Protocol.N_ADD:
				_apply_object_add(d)
			elif n == Protocol.N_REMOVE:
				_apply_object_remove(d)
		Protocol.T_PROP:
			_apply_prop(d)
		Protocol.T_RECORD:
			records.apply(n, d)
			record_changed.emit(int(d.get("entityId", 0)), n, d.get("ops", []))
		Protocol.T_VIEW:
			views.apply(n, d)
			view_changed.emit(int(d.get("entityId", 0)), n, d.get("ops", []))


func _apply_object_add(d: Dictionary) -> void:
	var id := int(d.get("entityId", 0))
	if id == 0:
		return
	var is_self := bool(d.get("isSelf", false))
	var e := Entity.new(id, str(d.get("kind", "")), is_self)
	e.props = (d.get("props", {}) as Dictionary).duplicate()
	entities[id] = e
	if is_self:
		self_id = id
	entity_added.emit(e)


func _apply_object_remove(d: Dictionary) -> void:
	var id := int(d.get("entityId", 0))
	if entities.erase(id):
		entity_removed.emit(id)


func _apply_prop(d: Dictionary) -> void:
	var id := int(d.get("entityId", 0))
	var e: Entity = entities.get(id)
	if e == null:
		return

	var changed := {}
	for k in d.keys():
		if k != "entityId":
			changed[k] = d[k]
	e.apply_props(changed)
	if d.has("seq"):
		e.last_seq = int(d["seq"])

	props_changed.emit(e, changed)


# ---------- 查询 ----------
# 技能列表, 按 id 排序后返回。
# 顺序即 onCastAbility 的 index 参数(index 从 1 开始) —— ui 面板与施法输入
# 共用本方法, 保证"面板上显示的第 N 个"就是"施放的第 N 个"。
func abilities(entity_id: int) -> Array:
	var view := views.get_view(entity_id, Protocol.VIEW_ABILITIES)
	var children: Dictionary = view["children"]
	var ids: Array = children.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		out.append(children[id])
	return out


func get_entity(id: int) -> Entity:
	return entities.get(id)


func get_self() -> Entity:
	return entities.get(self_id)


func other_entities() -> Array:
	var out: Array = []
	for id in entities.keys():
		if id != self_id:
			out.append(entities[id])
	return out


# ---------- 退出 / 重登清理 ----------
func clear() -> void:
	entities = {}
	records.clear()
	views.clear()
	self_id = 0
	cleared.emit()
