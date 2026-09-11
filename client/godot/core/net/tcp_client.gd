# tcp_client.gd — 与游戏网关(gate)的 TCP 连接。
# 只负责: 连接、发送帧、收包切帧、断线通知。不解释业务语义。
#
# 用法:
#   var tcp := TcpClient.new()
#   tcp.message.connect(func(msg): ...)
#   tcp.connect_to(host, port)
#   # 每帧调用 tcp.poll()
extends RefCounted
class_name TcpClient

signal connected
signal disconnected(reason: String)
# 每收到一条完整消息触发一次(已 JSON 解码)。
signal message(msg: Dictionary)

var host: String = "127.0.0.1"
var port: int = 8000

var _peer := StreamPeerTCP.new()
var _buffer := PackedByteArray()
var _connecting := false


func connect_to(p_host: String, p_port: int) -> void:
	close()
	host = p_host
	port = p_port
	_connecting = true
	var err := _peer.connect_to_host(host, port)
	if err != OK:
		_connecting = false
		disconnected.emit("connect failed: %d" % err)


# 每帧调用: 推进连接状态并读取所有可用字节。
func poll() -> void:
	_peer.poll()

	if _connecting:
		_poll_connecting()
		return

	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return

	_read_available()


func _poll_connecting() -> void:
	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			_connecting = false
			connected.emit()
		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			_connecting = false
			disconnected.emit("connect error")


func _read_available() -> void:
	var avail := _peer.get_available_bytes()
	while avail > 0:
		var chunk := _peer.get_data(avail)
		if chunk[0] != OK:
			break
		_buffer.append_array(chunk[1])
		avail = _peer.get_available_bytes()

	if _buffer.size() == 0:
		return

	var result := FrameCodec.decode_all(_buffer)
	_buffer = result["rest"]
	for msg in result["messages"]:
		_emit_expanded(msg)


# 展开 batch 信封后逐条发出。
#
# 服务器每个 tick 会把发给该玩家的多条消息合并成一帧 batch(见 doc/protocol.md 2.2)。
# 在这里展开, 使所有下游(登录状态机、世界状态、RPC 处理)都只看到普通消息,
# 无需各自感知 batch 的存在 —— batch 属于传输层细节。
func _emit_expanded(msg: Dictionary) -> void:
	if str(msg.get("t", "")) != Protocol.T_BATCH:
		message.emit(msg)
		return
	var d: Dictionary = msg.get("d", {})
	for inner in d.get(Protocol.D_BATCH_LIST, []):
		if typeof(inner) == TYPE_DICTIONARY:
			message.emit(inner)


func send(msg: Dictionary) -> void:
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	_peer.put_data(FrameCodec.encode(msg))


func send_envelope(t: String, n: String, d: Dictionary = {}) -> void:
	send(Protocol.envelope(t, n, d))


func send_rpc(method: String, d: Dictionary = {}) -> void:
	send(Protocol.rpc(method, d))


func is_open() -> bool:
	return _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED


func close() -> void:
	if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_peer.disconnect_from_host()
	_buffer = PackedByteArray()
	_connecting = false
