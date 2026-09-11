# session_phase.gd — 客户端启动到可游玩的阶段划分。
#
# 为什么需要显式的阶段:
#   从"启动游戏"到"可以开始玩"要经过多个异步步骤(HTTP 登录 / TCP / 鉴权 /
#   选角 / 等初始数据)。若把判断散在各处, 就无法回答"现在能不能玩了"。
#   显式阶段让主循环只需问一句 is_playable(), 各子系统据此启停。
#
# 阶段流转:
#   BOOT        进程启动, 尚未做任何网络动作
#   LOGIN_HTTP  HTTP 登录中(拿 token)
#   CONNECTING  连接 gate
#   AUTHING     发送 AUTH 并等待 auth_ok
#   CHARLIST    拉取角色列表
#   ENTERING    已发 selectCharacter, 等待世界初始数据
#   SYNCING     已进入世界, 等待**初始数据齐全**(见 WorldReady)
#   PLAYING     可游玩: 游戏内逻辑模块可开始执行
#   DISCONNECTED 断开/失败, 可重连
#
# 关键: SYNCING 与 PLAYING 的区别就是本文件存在的意义 ——
#   "收到 object add(isSelf)" 只说明实体创建了, 背包/技能等数据可能还没到;
#   必须等 WorldReady 判定齐全, 才算真正可玩。
extends RefCounted
class_name SessionPhase

signal changed(from: int, to: int)

enum Phase { BOOT, LOGIN_HTTP, CONNECTING, AUTHING, CHARLIST, ENTERING, SYNCING, PLAYING, DISCONNECTED }

const NAMES := {
	Phase.BOOT: "启动",
	Phase.LOGIN_HTTP: "HTTP 登录",
	Phase.CONNECTING: "连接网关",
	Phase.AUTHING: "鉴权",
	Phase.CHARLIST: "拉取角色",
	Phase.ENTERING: "进入世界",
	Phase.SYNCING: "同步初始数据",
	Phase.PLAYING: "游玩中",
	Phase.DISCONNECTED: "已断开",
}

var phase: int = Phase.BOOT


func set_phase(p: int) -> void:
	if p == phase:
		return
	var from := phase
	phase = p
	changed.emit(from, p)


# 是否已进入可游玩状态 —— 游戏内逻辑模块以此为准。
func is_playable() -> bool:
	return phase == Phase.PLAYING


# 是否在"世界内"(含 SYNCING: 已在世界, 但数据未齐)。
# 用于控制渲染/移动这类"可以早一点开始"的逻辑。
func is_in_world() -> bool:
	return phase == Phase.SYNCING or phase == Phase.PLAYING


func name_of(p: int = -1) -> String:
	return str(NAMES.get(phase if p < 0 else p, "?"))


func reset() -> void:
	set_phase(Phase.BOOT)
