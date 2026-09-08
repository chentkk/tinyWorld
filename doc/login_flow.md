# tinyWorld 登录 / 退出 / 重登录流程

> 服务端相关代码：
> - `server/tinyworld/app/login/login.lua`
> - `server/tinyworld/app/gate/gate.lua`
> - `server/tinyworld/app/baseapp/baseapp.lua`
> - `server/tinyworld/app/baseapp/baseentity.lua`
> - `server/tinyworld/app/cellapp/cellapp.lua`

## 1. 总览

```
客户端
  │ ① HTTP /login (login 服务)
  │    返回 { code, accountId, token }
  │
  │ ② TCP 连接 gate:8000
  │ ③ AUTH auth{ token }
  │ ④ 收到 AUTH auth_ok{ connId }
  │ ⑤ ACCOUNT characterList / createCharacter / selectCharacter
  │ ⑥ 收到 object add + record + view（进入世界）
  │ ⑦ RPC 交互
  │ ⑧ 断开 TCP 或服务器踢出（退出流程）
```

各服务职责：

| 服务 | 职责 |
|------|------|
| login | HTTP 校验账号/密码，签发 token（1 小时有效） |
| gate | 收/发网络帧，AUTH 后把消息转发给绑定的 baseapp；记录 message.log |
| baseapp | 会话管理、角色数据加载/保存、ACCOUNT 命令、base 侧业务 RPC |
| cellapp | 在 cell 内创建 real entity（真实对象），驱动 tick 与同步 |
| world | 空间/cell 划分、选择 spawn 点 |

## 2. 正常登录流程（详细）

### 第 1 步：HTTP 登录拿 token

```
GET /login?name=test1&password=123456
→ { "code": 0, "accountId": 1, "token": "1xxx" }
```

- token 有效期 3600 秒。
- 同一账号可签发多个 token。

### 第 2 步：TCP 连接 gate，AUTH 认证

```
connect 127.0.0.1:8000
send  { "t":"AUTH", "n":"auth", "d": {"token": "1xxx"} }
recv  { "t":"AUTH", "n":"auth_ok", "d": {"code":0,"accountId":1,"connId":"1-3","msg":"auth ok"} }
```

- AUTH 阶段只允许发 `AUTH` 消息；未认证发的其它消息**不会转发**到业务。
- AUTH 失败：收到 `AUTH auth_fail` 后服务器会关闭连接。
- 成功后 gate 会选择 baseapp 并发送 `open_client`，在 baseapp 建立 session。

### 第 3 步：拉取角色列表

```
send  { "t":"ACCOUNT", "n":"characterList", "d": {} }
recv  { "t":"ACCOUNT", "n":"characterList", "d": {"code":0,"characters":[...]} }
```

### 第 4 步：选择角色进入世界

```
send  { "t":"ACCOUNT", "n":"selectCharacter", "d": {"playerId":1} }
```

服务器依次下发（无确定性顺序，客户端应监听全部类型）：

1. `object add`（自己，`d.isSelf = true`）
2. `record current_tasks`（自己的任务表）
3. `view bag` / `view equipment`（打开的基础视图）
4. **稍后**：`view modifiers_view` / `view abilities_view`（cell 侧的 selfOnly 视图）
5. 最后：`ACCOUNT selectCharacter{ code = 0 }`

**客户端必须等收到 `object add` 且 `d.isSelf == true`，才算进入世界成功。**

### 第 5 步：世界交互

- 发送 RPC。
- 接收 `prop` / `record` / `view` / `object add` / `object remove` / RPC 推送。
- 客户端向服务器发 RPC 时，若方法不存在，服务器不会回包。

## 3. 当前端到端消息时序（实测 message.log）

以下为真实流程中 message.log 的收发记录样例：

```
[1-1] recv AUTH auth token=xxx
[1-1] send AUTH auth_ok code=0 accountId=1 connId=1-1 msg=auth ok
[1-1] recv ACCOUNT characterList
[1-1] send ACCOUNT characterList code=0 characters={...}
[1-1] recv ACCOUNT selectCharacter playerId=1
[1-1] send object add entityId<1> Player ...（isSelf 在 JSON 中为 true）
[1-1] send record current_tasks entityId<1> row<1>={add ...}
[1-1] send view bag entityId<1>
[1-1] send view equipment entityId<1>
[1-1] send ACCOUNT selectCharacter code=0 playerId=1
[1-1] send view modifiers_view entityId<1> ...
[1-1] send view abilities_view entityId<1> ...
```

## 4. 退出流程

客户端主动关闭 socket 或异常断线时：

```
(1) gate 的 reader 结束 → closeConn
(2) gate 写 disconnect 日志
(3) gate → baseapp.client_disconnect(connId)
(4) baseapp 清理 session
(5) baseapp 若实体已进入世界：
    a. 先 cellapp.get_entity 取最新坐标
    b. cellapp.despawn_entity 销毁 real
       - 触发 real.onDestroy（组件清理）
       - 清理该 real 的 ghost
       - 移出 cell（timer / spatial / players 索引）
    c. 保存角色数据到 player_bin
    d. 触发 base entity.onDestroy
(6) 日志：session closed
```

关键保障：
- `despawn_entity` 幂等；real 销毁会同步销毁 ghost。
- 断线保存前会取 cell 侧最新坐标。
- `gate` 的每个 `connect.` 必须有一个 `disconnect.` 日志（当前已验证）。

## 5. 重复登录 / 顶替登录

同一账号用新连接再次 AUTH 时：

1. baseapp `open_client` 检测到已有同 accountId 旧 session。
2. 向 gate 发 `kick(旧 connId)`。
3. 旧连接被服务器关闭，旧的 baseapp session 被 `client_disconnect` 清理（旧 real 销毁，旧数据保存）。
4. 新会话正常建立。

客户端行为：
- 旧连接会收到 **服务器主动关闭**（recv 返回空或超时）。
- 若脚本并发度高，旧连接可能在被踢前收到少量新会话世界数据（record/view 广播），属正常时序，客户端应以断开为准。

## 6. 未进入世界就断线的路径

- ACCOUNT 阶段（未 `selectCharacter`）断线：
  - session 无 base entity，`client_disconnect` 清理 session（无存盘，无 real 可销毁）。
- cellapp 上的 real 只在 `selectCharacter` 成功后才存在；退出时一定会被 despawn。

## 7. 异常场景

### 7.1 bad token
- 收到 `AUTH auth_fail` 后服务器立即断开。

### 7.2 未 AUTH 直接发业务消息
- gate 不转发，也不会回复；一段时间后由客户端自行断线或服务器在 AUTH 前拒绝。

### 7.3 角色不存在 / 不属于账号
- `selectCharacter` 返回 `code = 1, msg = "player not found"`。

### 7.4 spawn 失败
- `selectCharacter` 返回 `code = 1 / 2`（见协议文档）。

## 8. 客户端实现建议时序状态机

```
[IDLE] --HTTP login--> [AUTHING]
[AUTHING] --auth_ok--> [CHARLIST]
[AUTHING] --auth_fail--> [IDLE] (被断开)
[CHARLIST] --characterList--> [SENDING_SELECT]
[SENDING_SELECT] --object add(isSelf)--> [WORLD]
[WORLD] --disconnect / kick--> [IDLE]
```

- 任何状态解析/网络异常回到 `IDLE`（或重连）。
- `object add(isSelf)` 是进入 WORLD 的唯一触发器；不要依赖 `selectCharacter` 响应作为世界就绪信号（响应与 world 数据的顺序是异步的）。
