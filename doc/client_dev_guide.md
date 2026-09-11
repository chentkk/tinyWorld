# tinyWorld 客户端开发指南

> 面向新客户端会话。目标是：从零实现一个能登录、选角色、进入世界、收发世界数据的客户端。

## 1. 必要环境

- TCP socket + JSON 解析。
- 若用 LÖVE：客户端运行在 LuaJIT/Lua 5.1；注意 `string.pack/unpack` 不存在。
- 若用其他语言（C#/C++/Go/Python）：只要按 `protocol.md` 的帧格式即可。

## 2. 目录约定

本仓库现有两套客户端，都实现本文档描述的协议：

**Godot 客户端（主力，`client/godot/`）** —— 分层架构，依赖单向
（`core` 框架层 → `game` 玩法层 → `ui` 表现层，`scripts/main.gd` 只做装配）：

```
client/godot/
├── core/                 # 框架层: 与玩法无关
│   ├── protocol/         #   协议常量与消息构造
│   └── net/              #   帧编解码 / TCP / HTTP 登录
├── game/                 # 玩法层: 状态与规则
│   ├── session/          #   登录状态机
│   ├── world/            #   世界状态(entity/record/view)
│   └── movement/         #   移动预测与 Reconciliation
├── ui/                   # 表现层: 渲染与交互
│   ├── hud/panels/       #   各数据面板
│   ├── world/            #   网格 / 实体显示
│   └── combat/           #   战斗飘字
└── scripts/main.gd       # 入口装配
```

详见 `client/godot/README.md`。

**LÖVE Lua 客户端（已冻结，`tools/love_client/`）** —— 协议参考实现，目录如下：

```
tools/love_client/
├── main.lua              # 入口（状态机）
├── src/
│   ├── net.lua           # 网络帧收发、登录接口
│   ├── json.lua          # JSON（Lua 5.1 兼容）
│   ├── entities.lua      # 实体管理
│   ├── records.lua       # record 表格
│   ├── views.lua         # view 容器
│   ├── move.lua          # 移动客户端模拟与 Reconciliation
│   └── ui.lua            # UI
└── logs/
```

下文的最小实现示例沿用 Lua 写法（LuaJIT 无 `string.pack` 等），
概念对任何语言都适用。

## 3. 网络层最小实现

### 3.1 帧编解码

```lua
-- Lua 5.1 兼容的 uint16
local function packU16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end
local function unpackU16(s)
    return string.byte(s, 1) + string.byte(s, 2) * 256
end

function net.sendFrame(msg)
    local body = json.encode(msg)
    sock:send(packU16(#body) .. body)
end

-- 读缓冲切帧，粘包/半包都安全
local buffer = ""
function net.recvFrames()
    local chunk = sock:receive(10000)          -- 按实际 socket API 调整
    if chunk then buffer = buffer .. chunk end
    local out = {}
    while true do
        if #buffer < 2 then break end
        local len = unpackU16(buffer)
        if #buffer < 2 + len then break end
        local body = buffer:sub(3, 2 + len)
        buffer = buffer:sub(3 + len)
        out[#out + 1] = json.decode(body)
    end
    return out
end
```

### 3.2 建议封装

```lua
net.enqueue(t, n, d)     -- 发送一条 JSON 消息
net.onMessage = nil      -- 收到消息的回调 net.onMessage(msg)
net.selfId = nil         -- 进入世界后自己的 entityId
net.connId = nil         -- AUTH auth_ok 的 connId
```

## 4. 完整登录代码骨架

```lua
local HOST = "127.0.0.1"
local LOGIN_PORT = 8080
local GAME_PORT = 8000

-- 1) HTTP 登录
local function httpLogin(name, password)
    local http = require "socket.http"
    local body, code = http.request(string.format(
        "http://%s:%d/login?name=%s&password=%s",
        HOST, LOGIN_PORT, name, password))
    if code ~= 200 or not body then return nil end
    return json.decode(body) -- { code, accountId, token }
end

-- 2) 连接 + AUTH
local ok, err = net.connect(HOST, GAME_PORT)
assert(ok, err)
net.enqueue("AUTH", "auth", { token = loginResp.token })

-- 3) 处理消息
net.onMessage = function(msg)
    local d = msg.d or {}
    if msg.t == "AUTH" and msg.n == "auth_ok" then
        net.connId = d.connId
        net.enqueue("ACCOUNT", "characterList", {})
    elseif msg.t == "ACCOUNT" and msg.n == "characterList" then
        local chars = d.characters or {}
        if chars[1] then
            net.enqueue("ACCOUNT", "selectCharacter", { playerId = chars[1].id })
        end
    elseif msg.t == "object" and msg.n == "add" and d.isSelf then
        net.selfId = d.entityId
        onEnterWorld(d)
    elseif msg.t == "prop" then
        applyProp(d)
    elseif msg.t == "record" then
        applyRecord(d)
    elseif msg.t == "view" then
        applyView(d)
    elseif msg.t == "RPC" then
        onRpc(d)
    elseif msg.t == "object" and msg.n == "remove" then
        onObjectRemove(d)
    end
end
```

## 5. 实体与状态维护

### 5.1 建议实体结构

```lua
entities = {
    [entityId] = {
        entityId = ...,
        kind = "Player",
        props = {},          -- key -> value（含 x, y, hp, ...）
        records = {          -- recordName -> { [key] = row }
            current_tasks = {}
        },
        views = {            -- viewName -> {
            bag = { props = {}, children = { [id] = child } }
        },
        isSelf = false,
    }
}
```

### 5.2 object add / remove

- `object add`：创建/更新实体 `props`（全量）。
- `object remove`：从 `entities` 移除。

### 5.3 prop props

- 对 `entities[entityId].props` 做增量 merge。
- 若 `d.seq` 存在且 entity 是自己：用于移动 Reconciliation。

### 5.4 record op

- `add`：`records[name][key] = op.data`（若原来没有 key，可以先建空行再覆盖）。
- `remove`：`records[name][key] = nil`。
- `set`：merge 到已有行 `records[name][key]`。

### 5.5 view op

- `add`：`views[name].children[id] = op.data`。
- `remove`：`views[name].children[id] = nil`。
- `set`：merge 到 `views[name].children[id]`。
- `view`：merge 到 `views[name].props`。

## 6. 移动客户端参考（Reconciliation）

当前服务器 Move 组件：

- 客户端发 `onRequestMove { seq, dt, dirX, dirY }`。
- 服务器在 tick 内批量按服务器速度推演，`entity:set("x",...)` 会走属性同步。
- 自己收到的 `prop props` 会带 `seq`（服务器最后处理的移动号）。

客户端建议策略：
1. 本地按输入速度预测 `x,y` 并渲染。
2. 收到服务器 `prop props` 时校正 `x,y`。
3. `seq` 用于放弃已过期的本地预测。

## 7. 待监听服务端事件

| 事件 | 触发 | 建议处理 |
|------|------|---------|
| `AUTH auth_fail` | token 无效 | 关闭 socket，回登录页 |
| 服务器断开 | 异常 / 顶替 | 清理本地状态，可重连 |
| `object add` | 实体进入视野 | 建实体；若 `isSelf` 记录 selfId |
| `object remove` | 实体离开视野 | 删实体 |
| `prop props` | 属性同步 | merge props；校正移动 |
| `record <n>` | 表格同步 | 应用 record ops |
| `view <n>` | 视图同步 | 应用 view ops |
| `RPC onCombatDamage/Heal` | 战斗事件 | UI 表现/飘字 |

## 8. 调试建议

- 登录前在本地写 `message.log`（可选），与服务器 `game/logs/message.log` 对照。
- 服务器日志：`SERVER/skynet.log` 或重定向文件。
- 验证要点：
  - `AUTH auth_ok → ACCOUNT characterList → ACCOUNT selectCharacter → object add(isSelf)`。
  - 世界数据 `record current_tasks`、`view bag/equipment` 应收到。
  - 断线后服务器 `message.log` 应有 `disconnect.` 且可配对。

## 9. 测试用账号（真实 mysql）

| 账号 | 密码 | 可用角色 |
|------|------|---------|
| test1 | 123456 | 角色 id=1 … |
| ... | ... | 当前共有 10 个账号 test1~test10，密码 123456 |

真实登录用 mysql；无 mysql 时可用 `db_mode=mock`（仅本地调试）。
