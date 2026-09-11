# frame_codec.gd — tinyWorld 帧编解码: 2 字节小端长度 + JSON 负载。
# 纯函数, 不持有 socket, 便于单独测试。
extends RefCounted
class_name FrameCodec

# 把一条消息编码成完整网络帧。
static func encode(msg: Dictionary) -> PackedByteArray:
	var body := JSON.stringify(msg).to_utf8_buffer()
	var frame := PackedByteArray()
	var length := body.size()
	frame.resize(2)
	frame[0] = length & 0xFF
	frame[1] = (length >> 8) & 0xFF
	frame.append_array(body)
	return frame


# 从读缓冲中切出所有完整帧。
# 返回 { messages: Array[Dictionary], rest: PackedByteArray }。
# 半包(数据不足)会留在 rest 中等待下次; 粘包(多帧一起到达)会全部切出。
static func decode_all(buffer: PackedByteArray) -> Dictionary:
	var messages: Array = []
	var offset := 0
	var total := buffer.size()

	while total - offset >= 2:
		var length: int = buffer[offset] | (buffer[offset + 1] << 8)
		if total - offset < 2 + length:
			break
		var body := buffer.slice(offset + 2, offset + 2 + length).get_string_from_utf8()
		offset += 2 + length
		var parsed: Variant = JSON.parse_string(body)
		if typeof(parsed) == TYPE_DICTIONARY:
			messages.append(parsed)

	return { "messages": messages, "rest": buffer.slice(offset) }
