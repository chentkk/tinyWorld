# http_login.gd — 登录 HTTP 接口。
# GET /login?name=<账号>&password=<密码> -> { code, accountId, token }
# 使用 HTTPClient 手动轮询(不依赖场景树, 无窗口/headless 下也可用)。
extends RefCounted
class_name HttpLogin

const TIMEOUT := 8.0


# 返回 { code, accountId, token } 或 { code, msg }。code != 0 视为失败。
static func login(host: String, port: int, account: String, password: String) -> Dictionary:
	var client := HTTPClient.new()
	var err := client.connect_to_host(host, port)
	if err != OK:
		return { "code": -1, "msg": "http connect err %d" % err }

	var waited := await _wait_status(client, [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING])
	if waited < 0.0:
		client.close()
		return { "code": -1, "msg": "http connect timeout" }
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		client.close()
		return { "code": -1, "msg": "http connect failed" }

	var path := "/login?name=%s&password=%s" % [account.uri_encode(), password.uri_encode()]
	client.request(HTTPClient.METHOD_GET, path, PackedStringArray())
	if await _wait_status(client, [HTTPClient.STATUS_REQUESTING]) < 0.0:
		client.close()
		return { "code": -1, "msg": "http request timeout" }

	var body := PackedByteArray()
	if client.has_response():
		var deadline := TIMEOUT
		while client.get_status() == HTTPClient.STATUS_BODY and deadline > 0.0:
			client.poll()
			body.append_array(client.read_response_body_chunk())
			await Engine.get_main_loop().process_frame
			deadline -= 0.016
	client.close()

	var text := body.get_string_from_utf8()
	if text.length() == 0:
		return { "code": -1, "msg": "empty http response" }
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return { "code": -1, "msg": "bad http response" }
	return parsed


# 轮询直到离开 statuses 中的状态。返回耗时(秒), 超时返回 -1。
static func _wait_status(client: HTTPClient, statuses: Array) -> float:
	var waited := 0.0
	while client.get_status() in statuses:
		client.poll()
		await Engine.get_main_loop().process_frame
		waited += 0.016
		if waited > TIMEOUT:
			return -1.0
	return waited
