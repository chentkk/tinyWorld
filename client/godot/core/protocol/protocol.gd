# protocol.gd — tinyWorld 协议常量与消息构造。
# 与 server/tinyworld/net/protocol.lua 保持一致; 只放"协议长什么样"的知识,
# 不做任何 IO, 因此 core/net 与 game 层都可安全引用。
#
# 信封: { t: <大类>, n: <名称>, d: <数据> }
extends RefCounted
class_name Protocol

# ---------- 消息大类 (t) ----------
const T_AUTH := "AUTH"
const T_ACCOUNT := "ACCOUNT"
const T_RPC := "RPC"
const T_OBJECT := "object"
const T_PROP := "prop"
const T_RECORD := "record"
const T_VIEW := "view"
# 批量信封: 服务器每个 tick 把发给同一玩家的所有同步消息合并成一帧,
# 减少跨服务发送与编码。客户端需按顺序展开逐条处理, 语义与逐条收到一致。
# 见 doc/protocol.md 2.2 与 server/tinyworld/net/protocol.lua 的 M.batch()。
const T_BATCH := "batch"
const N_BATCH_MSGS := "msgs"
const D_BATCH_LIST := "msgs"

# ---------- AUTH ----------
const N_AUTH := "auth"
const N_AUTH_OK := "auth_ok"
const N_AUTH_FAIL := "auth_fail"

# ---------- ACCOUNT ----------
const N_CHARACTER_LIST := "characterList"
const N_CREATE_CHARACTER := "createCharacter"
const N_SELECT_CHARACTER := "selectCharacter"
const N_SPACE_INFO := "spaceInfo"

# ---------- object ----------
const N_ADD := "add"
const N_REMOVE := "remove"

# ---------- 客户端 -> 服务器 RPC 方法名 ----------
const RPC_MOVE := "onRequestMove"
const RPC_STOP_MOVE := "onStopMove"
const RPC_MOVE_BAG_ITEM := "onMoveBagItem"
const RPC_EQUIP_ITEM := "onEquipItem"
const RPC_UNEQUIP_ITEM := "onUnequipItem"
const RPC_ACCEPT_TASK := "onAcceptTask"
const RPC_CAST_ABILITY := "onCastAbility"

# ---------- 服务器 -> 客户端 RPC 事件 ----------
const EV_COMBAT_DAMAGE := "onCombatDamage"
const EV_COMBAT_HEAL := "onCombatHeal"
const EV_SPELL_CAST := "onSpellCast"

# ---------- 视图 / 表格名 ----------
const VIEW_BAG := "bag"
const VIEW_EQUIPMENT := "equipment"
const VIEW_ABILITIES := "abilities_view"
const VIEW_MODIFIERS := "modifiers_view"
const RECORD_CURRENT_TASKS := "current_tasks"

# ---------- 移动参数(与服务器 Move 组件一致) ----------
# 单包 dt 的服务器上限(见 server/game/cell/move.lua: math.min(dt, 0.2))。
# 客户端按帧间隔发送, dt 需按此封顶。
const MOVE_DT_MAX := 0.2
# 移动包发送间隔(秒)。本地预测每帧进行, 但**发包**按此间隔打包, 以降低带宽
# (MMORPG 人数多时, 每帧发包会让移动流量线性膨胀)。100ms = 10 包/秒。
# 方向变化时会立即冲刷一个包, 保证包内方向恒定且转向无延迟。
const MOVE_SEND_INTERVAL := 0.1
# speed 不再在此硬编码: 它是服务端下发的实体属性(props.speed),
# 由 MovePredictor.set_speed() 同步, 避免本地预测与服务器推演速度不一致。


static func envelope(t: String, n: String, d: Dictionary = {}) -> Dictionary:
	return { "t": t, "n": n, "d": d }


static func rpc(method: String, d: Dictionary = {}) -> Dictionary:
	return envelope(T_RPC, method, d)
