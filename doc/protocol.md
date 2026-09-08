# tinyWorld 通信协议文档

> 面向客户端开发者。文档与 `server/tinyworld/net/protocol.lua`、`server/tinyworld/core/proto.lua` 保持一致。
> 若服务端代码有更新，以代码为准。

## 1. 传输层

- TCP 明文连接。
- 游戏网关默认端口：**8000**。
- 登录 HTTP 默认端口：**8080**。

### 1.1 二进制帧格式

每个网络消息帧：

```
+------------------+-----------------------+
| 2 字节小端长度 L  | JSON 负载（L 字节）     |
+------------------+-----------------------+
```

- `L`：负载（JSON 字符串）的**字节数**，`uint16` 小端。
- 负载：UTF-8 编码的 JSON 文本。

**Lua 5.1 / LuaJIT 提示**：没有 `string.pack/unpack`，需要手写：

```lua
local function packU16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end
local function unpackU16(s)
    return string.byte(s, 1) + string.byte(s, 2) * 256
end
```

### 1.2 JSON 编解码

- 负载使用 JSON。
- 服务端 JSON 实现：`server/tinyworld/core/json.lua`（Lua 5.3/5.5 用自研实现）。
- 客户端若在 LÖVE/LuaJIT (5.1) 下，需要自带 JSON 库（现有客户端使用 `client/src/json.lua`）。

## 2. 消息信封

所有业务消息都是一个 JSON 对象：

```json
{ "t": "<消息类型>", "n": "<消息名称>", "d": { ... } }
```

- `t` (type)：消息大类。
- `n` (name)：消息名称。
- `d` (data)：消息数据，对象。**缺省视为空对象 `{}`**。

### 2.1 消息大类（t）

| t       | 说明 |
|---------|------|
| `AUTH`    | 登录认证 |
| `ACCOUNT` | 账号/角色管理（选角前） |
| `RPC`     | 业务远程调用（进入世界后） |
| `object`  | 对象（实体）进入/离开视野 |
| `prop`    | 实体属性增量同步 |
| `record`  | 表格（Record）同步 |
| `view`    | 容器/视图（View）同步 |

## 3. HTTP 登录接口

### 3.1 请求

```
GET http://<host>:8080/login?name=<账号>&password=<密码>
```

- `name`：账号名，如 `test1`。
- `password`：明文密码。

### 3.2 响应

HTTP 200，正文为 JSON：

```json
{
  "code": 0,
  "accountId": 1,
  "token": "1a2b3c4d5e6f7a8b"
}
```

字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `code` | number | `0` 成功；`1` 账号不存在；`2` 密码错误 |
| `accountId` | number | 账号 id（仅登录成功时返回） |
| `token` | string | 登录 token，后续 AUTH 使用 |

**注意**：
- token 有效期 1 小时。
- 同一账号可多次登录并获得多个 token；后建立的连接会"顶替"旧连接（见登录流程文档）。

## 4. 登录/账号阶段协议

### 4.1 AUTH auth（客户端 → 服务器）

发送：

```json
{ "t": "AUTH", "n": "auth", "d": { "token": "<token>" } }
```

### 4.2 AUTH auth_ok（服务器 → 客户端）

登录成功响应：

```json
{
  "t": "AUTH",
  "n": "auth_ok",
  "d": {
    "code": 0,
    "accountId": 1,
    "connId": "1-3",
    "msg": "auth ok"
  }
}
```

- `connId`：本次连接号，格式 `"gateId-序号"`（如 `"1-3"`）。

### 4.3 AUTH auth_fail（服务器 → 客户端）

token 错误：

```json
{ "t": "AUTH", "n": "auth_fail", "d": { "code": 1, "msg": "bad token" } }
```

收到后服务器会立即关闭连接。

### 4.4 ACCOUNT characterList（客户端 → 服务器 / 服务器 → 客户端）

请求：

```json
{ "t": "ACCOUNT", "n": "characterList", "d": {} }
```

响应：

```json
{
  "t": "ACCOUNT",
  "n": "characterList",
  "d": {
    "code": 0,
    "characters": [
      { "id": 1, "account_id": 1, "name": "test1", "level": 1,
        "hp": 100, "max_hp": 100, "mp": 100, "max_mp": 100,
        "gold": 0, "scene": "main", "x": 999.0, "y": 999.0 }
    ]
  }
}
```

- `characters` 数组每个元素是一个数据库玩家行（字段来自 `players` 表）。

### 4.5 ACCOUNT createCharacter（客户端 → 服务器 / 服务器 → 客户端）

请求：

```json
{ "t": "ACCOUNT", "n": "createCharacter", "d": { "name": "角色名" } }
```

成功：服务器会用新的完整 `characterList` 消息应答（`n = "characterList"`）。
失败：`{ "t": "ACCOUNT", "n": "createCharacter", "d": { "code": 1, "msg": "create fail" } }`

### 4.6 ACCOUNT spaceInfo（客户端 → 服务器 / 服务器 → 客户端）

请求：

```json
{ "t": "ACCOUNT", "n": "spaceInfo", "d": {} }
```

响应 `d` 为该空间信息：

```json
{
  "id": "main",
  "width": 200,
  "height": 200,
  "cellSize": 50,
  "aoiRange": 20,
  "ghostRange": 40,
  "balance": { "enabled": false, "strategy": 2 },
  "cells": [ { "id": "0:0", "x": 0, "y": 0, "w": 50, "h": 50, "appId": 1 } ]
}
```

- `cells` 每个 cell 由 `CellInfo` dump 得到（字段取决于服务端 `space.cell_info` 的实现）。

### 4.7 ACCOUNT selectCharacter（客户端 → 服务器 / 服务器 → 客户端）

请求：

```json
{ "t": "ACCOUNT", "n": "selectCharacter", "d": { "playerId": 1 } }
```

- `playerId` 必须是该账号拥有的角色 id。

进入世界成功时，服务器**先**发 world 数据（`object add` / `record` / `view`），**再**回 ACCOUNT 响应：

```json
{ "t": "ACCOUNT", "n": "selectCharacter", "d": { "code": 0, "playerId": 1 } }
```

失败场景：

| code | msg             | 说明 |
|------|-----------------|------|
| 1 | player not found | 角色不存在或不属于该账号 |
| 1 | no spawn info    | 无法选择出生点 |
| 2 | spawn fail       | cellapp 创建实体失败 |

## 5. 进入世界后的同步消息

进入世界后，客户端会陆续收到：

### 5.1 object add（服务器 → 客户端）

对象进入视野：

```json
{
  "t": "object",
  "n": "add",
  "d": {
    "entityId": 1,
    "kind": "Player",
    "props": { "x": 999, "y": 999, "hp": 100, /* ... 全部同步属性 */ },
    "isSelf": true            // 仅当该实体是"自己"时为 true
  }
}
```

- `isSelf` 只出现在自己身上（当前账号选中的角色）。
- `props` 是全量属性快照。

### 5.2 object remove（服务器 → 客户端）

对象离开视野：

```json
{ "t": "object", "n": "remove", "d": { "entityId": 1 } }
```

### 5.3 prop props（服务器 → 客户端）

实体属性增量同步：

```json
{
  "t": "prop",
  "n": "props",
  "d": {
    "entityId": 1,
    "x": 100.0,
    "y": 200.0,
    "seq": 42                    // 仅自己的移动包可能带 seq（Reconciliation）
    // ... 其余变更字段
  }
}
```

- 只包含发生变化且需要同步的属性。
- 自身移动包的 `seq` 是服务器确认的最后移动序号。

### 5.4 record <表名>（服务器 → 客户端）

表格增量同步：

```json
{
  "t": "record",
  "n": "current_tasks",       // RecordDef.name
  "d": {
    "entityId": 1,
    "ops": [
      { "type": "add", "key": "99001", "data": { "taskid": 99001, "state": 0, "progress": 0 } },
      { "type": "remove", "key": "99001" },
      { "type": "set", "key": "99001", "data": { "progress": 5 } }
    ]
  }
}
```

op 类型：

| type | 字段 | 说明 |
|------|------|------|
| `add` | `key`, `data` | 新增一行，`data` 是同步字段快照 |
| `remove` | `key` | 删除一行 |
| `set` | `key`, `data` | 修改一行，`data` 只含变更字段 |

- `key` 是字符串；多主键时用 `":"` 拼接，如 `"owner:slot"`。
- 全量进入世界时，record 会以 `add` op 逐行下发。

### 5.5 view <视图名>（服务器 → 客户端）

容器/视图增量同步：

```json
{
  "t": "view",
  "n": "bag",                 // ContainerDef.name
  "d": {
    "entityId": 1,
    "ops": [
      { "type": "add", "id": 0, "data": { "id": 0, "slot": 0, "itemId": 7001, "count": 3 } },
      { "type": "remove", "id": 0 },
      { "type": "set", "id": 0, "data": { "count": 5 } },
      { "type": "view", "data": { "capacity": 32 } }   // 容器自身属性变化
    ]
  }
}
```

op 类型：

| type | 字段 | 说明 |
|------|------|------|
| `add` | `id`, `data` | 添加子对象，`data` 是子对象全量数据 |
| `remove` | `id` | 删除子对象 |
| `set` | `id`, `data` | 修改子对象，`data` 只含变更字段 |
| `view` | `data` | 容器**自身**属性变化（不含 id） |

- 子对象 `data` 可能包含它自己的 records 字段（嵌套 `recordName -> {行 key -> 数据}`）。
- 全量进入世界时，view 以 `add` op 逐个下发子对象。
- `selfOnly` 视图（如 `modifiers_view` / `abilities_view`）只发给自己的玩家对象。

## 6. RPC 协议

进入世界后，客户端通过 RPC 与服务器交互。

### 6.1 客户端 → 服务器 RPC 请求

```json
{ "t": "RPC", "n": "<方法名>", "d": { ... } }
```

### 6.2 服务器 → 客户端 RPC 响应

```json
{ "t": "RPC", "n": "<方法名>", "d": { ... } }
```

- 若该 RPC 在 baseapp 注册，由 baseapp 直接回包。
- 若该 RPC 只在 cellapp 上注册，会转发给 real 处理，再由 baseapp 回包。
- **未注册的方法不回复**；进入世界前发 RPC 也不回复。

## 7. 当前已实现的客户端 RPC 方法

| 方法名 | 所在组件/端 | 参数 | 返回 `d` |
|--------|-----------|------|----------|
| `onRequestMove` | Move (cell) | `{ seq, dt?, dirX, dirY }` | `nil` 或 `{code=1,msg="need seq"}` |
| `onStopMove` | Move (cell) | `{}` | `nil` |
| `onMoveBagItem` | Bag (base) | `{ fromId, toSlot }` | `nil` 或 `{code=1,msg="item not found"}` |
| `onEquipItem` | Equipment (base) | `{ bagId, slotName? }` | `nil` 或 `{code=1,msg="no item"}` / `{code=2,msg="slot used"}` |
| `onUnequipItem` | Equipment (base) | `{ slotName }` | `nil` 或 `{code=1,msg="no equip"}` |
| `onAcceptTask` | Task (base) | `{ taskid }` | `nil` 或 `{code=1,msg="bad task"}` / `{code=2,msg="task exists"}` |
| `onCastAbility` | CombatAgent (cell) | `{ targetId?, index? }` | `{code=0,msg="cast ok"}` 或错误 code |

移动参数说明：
- `seq`：客户端移动包自增序号（必需）。
- `dt`：本次移动持续秒数（可选，服务器会截断到 0.2 上限）。
- `dirX` / `dirY`：方向向量（服务器会归一化）。

## 8. 服务器主动推送的 RPC 事件（Combat）

服务器战斗事件通过 `t = "RPC"` 推送，客户端应监听：

### 8.1 onCombatDamage

```json
{ "t": "RPC", "n": "onCombatDamage", "d": {
  "entityId": 1, "attackerId": 2, "amount": 50,
  "damageType": "physical", "skill": "ability_mist_coil" } }
```

### 8.2 onCombatHeal

```json
{ "t": "RPC", "n": "onCombatHeal", "d": {
  "entityId": 1, "casterId": 2, "amount": 80, "healType": "spell" } }
```

（字段可能随战斗系统扩展。）

## 9. 属性同步语义

- 每条属性定义有 `sync`：`"all"`（自己+周围都能看到）、`"self"`（只有自己）、`"none"`（不同步）。
- 自身的 `prop props` 包包含所有 dirty 属性；
- 周围实体（非自己）的 `prop props` 只包含 `sync == "all"` 的 dirty 属性。

## 10. 二进制/文本边界注意事项

- 断包检测：读满 2 字节得 L，再读 L 字节，不足则等待下次。
- 半包/粘包：严格按帧长度切分。
- JSON 解码失败应断开/忽略该连接。
- 服务器会在连接异常时强制关闭；客户端应正确处理 `recv` 返回空/超时。
