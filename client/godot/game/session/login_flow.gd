# login_flow.gd — 登录 / 选角 / 进入世界的状态机。
#
# 状态流转(与 doc/login_flow.md 一致):
#   IDLE --HTTP login--> CONNECTING --TCP ok--> AUTHING
#   AUTHING --auth_ok--> CHARLIST --characterList--> ENTERING
#   ENTERING --object add(isSelf)--> WORLD
#   任意状态 --断线/auth_fail--> 回 IDLE(可重连)
#
# 关键: 进入 WORLD 的唯一触发器是 "object add 且 isSelf == true",
# 不能依赖 selectCharacter 响应(它与 world 数据的顺序是异步的)。
extends RefCounted
class_name LoginFlow

signal state_changed(state: int)
signal logged(message: String)
signal failed(message: String)
signal entered_world(self_id: int)
# 空间几何(ACCOUNT spaceInfo)。width/height 用作世界边界。
signal space_info(width: float, height: float)

enum State { IDLE, CONNECTING, AUTHING, CHARLIST, ENTERING, WORLD }

const LOGIN_PORT := 8080
const GAME_PORT := 8000

var host: String = "127.0.0.1"
var account: String = "test1"
var password: String = "123456"

var state: int = State.IDLE
var token: String = ""
var account_id: int = 0
var conn_id: String = ""
var roles: Array = []

var _tcp: TcpClient


func _init(p_tcp: TcpClient) -> void:
	_tcp = p_tcp
	_tcp.connected.connect(_on_tcp_connected)
	_tcp.disconnected.connect(_on_tcp_disconnected)
	_tcp.message.connect(_on_message)


# 启动完整登录流程(HTTP -> TCP -> AUTH)。
func start(p_host: String, p_account: String, p_password: String) -> void:
	host = p_host
	account = p_account
	password = p_password
	_set_state(State.IDLE)
	logged.emit("HTTP 登录中...")

	var res := await HttpLogin.login(host, LOGIN_PORT, account, password)
	if int(res.get("code", -1)) != 0:
		_fail("登录失败: %s" % str(res.get("msg", res)))
		return

	token = str(res.get("token", ""))
	account_id = int(res.get("accountId", 0))
	logged.emit("HTTP 登录成功 accountId=%d" % account_id)

	_set_state(State.CONNECTING)
	_tcp.connect_to(host, GAME_PORT)


# 命名避开 Object.disconnect(信号方法), 故用 close 而非 disconnect。
func close() -> void:
	_tcp.close()
	_set_state(State.IDLE)


# ---------- TCP 事件 ----------
func _on_tcp_connected() -> void:
	logged.emit("TCP 已连接, 发送 AUTH")
	_set_state(State.AUTHING)
	_tcp.send_envelope(Protocol.T_AUTH, Protocol.N_AUTH, { "token": token })


func _on_tcp_disconnected(reason: String) -> void:
	logged.emit("连接断开: %s" % reason)
	if state != State.IDLE:
		_set_state(State.IDLE)
		failed.emit(reason)


# ---------- 消息处理 ----------
func _on_message(msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	var n := str(msg.get("n", ""))
	var d: Dictionary = msg.get("d", {})

	match t:
		Protocol.T_AUTH:
			_handle_auth(n, d)
		Protocol.T_ACCOUNT:
			_handle_account(n, d)
		Protocol.T_OBJECT:
			_handle_object(n, d)


func _handle_auth(n: String, d: Dictionary) -> void:
	match n:
		Protocol.N_AUTH_OK:
			conn_id = str(d.get("connId", ""))
			account_id = int(d.get("accountId", account_id))
			logged.emit("AUTH ok connId=%s" % conn_id)
			_set_state(State.CHARLIST)
			_tcp.send_envelope(Protocol.T_ACCOUNT, Protocol.N_CHARACTER_LIST, {})
		Protocol.N_AUTH_FAIL:
			_fail("鉴权失败: %s" % str(d.get("msg", "")))


func _handle_account(n: String, d: Dictionary) -> void:
	match n:
		Protocol.N_CHARACTER_LIST:
			roles = d.get("characters", [])
			if roles.is_empty():
				logged.emit("无角色, 创建新角色")
				_tcp.send_envelope(Protocol.T_ACCOUNT, Protocol.N_CREATE_CHARACTER, { "name": account })
				return
			var first: Dictionary = roles[0]
			var player_id := int(first.get("id", 0))
			logged.emit("选择角色 id=%d name=%s" % [player_id, str(first.get("name", "?"))])
			_set_state(State.ENTERING)
			_tcp.send_envelope(Protocol.T_ACCOUNT, Protocol.N_SELECT_CHARACTER, { "playerId": player_id })
			# spaceInfo 仅用于调试展示空间几何, 不阻塞进入世界。
			_tcp.send_envelope(Protocol.T_ACCOUNT, Protocol.N_SPACE_INFO, {})
		Protocol.N_SELECT_CHARACTER:
			if int(d.get("code", 0)) != 0:
				_fail("进入世界失败: %s" % str(d.get("msg", "")))
		Protocol.N_SPACE_INFO:
			logged.emit("spaceInfo: %s (%sx%s)" % [
				str(d.get("id", "")), str(d.get("width", "?")), str(d.get("height", "?"))])
			space_info.emit(
				float(d.get("width", 0.0)), float(d.get("height", 0.0)))


func _handle_object(n: String, d: Dictionary) -> void:
	if n != Protocol.N_ADD:
		return
	if not bool(d.get("isSelf", false)):
		return
	# 进入世界的唯一触发器。
	var self_id := int(d.get("entityId", 0))
	logged.emit("进入世界! selfId=%d kind=%s" % [self_id, str(d.get("kind", ""))])
	_set_state(State.WORLD)
	entered_world.emit(self_id)


func _set_state(s: int) -> void:
	state = s
	state_changed.emit(s)


func _fail(message: String) -> void:
	_set_state(State.IDLE)
	logged.emit(message)
	failed.emit(message)


func is_in_world() -> bool:
	return state == State.WORLD
