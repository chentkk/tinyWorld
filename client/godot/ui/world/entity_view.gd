# entity_view.gd — 实体显示层: 维护 entityId -> ActorNode 的映射。
#
# 位置来源:
#   自己  —— 由 MovePredictor 驱动(本地预测 + Reconciliation), 外部直接设置;
#   他人  —— 用位置更新的两端做插值, 避免瞬移。
#
# 动作/朝向来源:
#   自己  —— 由外部根据输入设置(见 main.gd);
#   他人  —— 从服务器同步的 dir 属性推导朝向; 位置在动 = 走路, 停下超时回站立。
extends Node2D
class_name EntityView

const LERP_SPEED := 8.0          # 其他实体插值收敛速度
const WALK_TIMEOUT := 0.25       # 多久没收到位移就认为停止走路(秒)

var entity_nodes: Dictionary = {}   # entityId -> ActorNode

var _lerp: Dictionary = {}          # entityId -> { to: Vector2 }
var _walk_timer: Dictionary = {}    # entityId -> 剩余"走路中"时间


func clear() -> void:
	for node in entity_nodes.values():
		node.teardown()          # 释放资源引用
		node.queue_free()
	entity_nodes.clear()
	_lerp.clear()
	_walk_timer.clear()


func has_entity(id: int) -> bool:
	return entity_nodes.has(id)


func get_node_for(id: int) -> ActorNode:
	return entity_nodes.get(id)


func add_entity(entity: Entity) -> void:
	var node := ActorNode.new()
	node.name = "E%d" % entity.entity_id
	node.setup(entity.entity_id, entity.kind, entity.is_self)
	node.refresh(entity)
	node.position = entity.position()
	# 进入视野时 object add 的 props 已带 dir(全量)。
	node.set_facing_radians(_dir_of(entity))
	add_child(node)
	entity_nodes[entity.entity_id] = node


func remove_entity(id: int) -> void:
	var node: ActorNode = entity_nodes.get(id)
	if node != null:
		# 先释放该实体占用的资源引用(序列帧由 AssetCache 按引用计数管理),
		# 再销毁节点, 避免长时间游玩后显存堆积。
		node.teardown()
		node.queue_free()
	entity_nodes.erase(id)
	_lerp.erase(id)
	_walk_timer.erase(id)


# 属性变化: 刷新显示; 位置变化驱动他人插值与走路动作。
func update_entity(entity: Entity, changed: Dictionary) -> void:
	var node: ActorNode = entity_nodes.get(entity.entity_id)
	if node == null:
		return
	node.refresh(entity)

	if entity.is_self:
		# 自己的位置与朝向由 main 根据输入直接设置, 这里不动。
		return

	# 他人: 服务器下发的 dir 变化 -> 更新朝向(增量 prop props 里的 d.dir)。
	if changed.has("dir"):
		node.set_facing_radians(_dir_of(entity))

	if entity.is_moving_prop(changed):
		_lerp[entity.entity_id] = { "to": entity.position() }
		_walk_timer[entity.entity_id] = WALK_TIMEOUT
		node.set_action(ActorNode.Action.WALK)


# 自己: 设置朝向(连续角度, 弧度)与是否在移动。
# 本地预测用: 按下方向键立即转向, 不等服务器回包。
func set_self_facing(radians: float, moving: bool) -> void:
	for id in entity_nodes.keys():
		var node: ActorNode = entity_nodes[id]
		if not node.is_self:
			continue
		node.set_facing_radians(radians)
		node.set_action(ActorNode.Action.WALK if moving else ActorNode.Action.IDLE)
		return


# 设置自己的位置。位置由 MovePredictor 独占维护(每帧累积 + 回包校正),
# 它输出的序列本身就是平滑的(实测每帧位移标准差为 0), 故这里直接渲染, 不再做二次平滑。
func set_self_position(pos: Vector2) -> void:
	for id in entity_nodes.keys():
		var node: ActorNode = entity_nodes[id]
		if node.is_self:
			node.position = pos
			return


# 播放一次攻击动作(自己或指定实体)。
func play_attack(entity_id: int) -> void:
	var node: ActorNode = entity_nodes.get(entity_id)
	if node != null:
		node.play_once(ActorNode.Action.ATTACK)


func _dir_of(entity: Entity) -> float:
	# 服务器 dir 为连续角度(弧度, 见 server Move:onTick); 未同步时默认 0(向右)。
	return float(entity.get_prop("dir", 0.0))


func _process(delta: float) -> void:
	# 他人位置插值。
	for id in _lerp.keys():
		var node: ActorNode = entity_nodes.get(id)
		if node == null:
			_lerp.erase(id)
			continue
		var to: Vector2 = _lerp[id]["to"]
		node.position = node.position.lerp(to, min(1.0, delta * LERP_SPEED))
		if node.position.distance_to(to) < 0.5:
			_lerp.erase(id)

	# 走路动作超时回站立。
	for id in _walk_timer.keys():
		var left: float = _walk_timer[id] - delta
		if left <= 0.0:
			_walk_timer.erase(id)
			var node: ActorNode = entity_nodes.get(id)
			if node != null:
				node.set_action(ActorNode.Action.IDLE)
		else:
			_walk_timer[id] = left
