# tinyWorld 交接文档

本仓库位于 `/root/test/testv3`。服务器在 `/root/test/testv3/server`，客户端在 `/root/test/testv3/client`。

- 远端仓库：`git@github.com:chentkk/tinyWorld.git`（当前分支 `main`）
- 最新提交：`50b1a50 refactor(server): reorganize code, unify protocol, fix login/logout flow`
- 协议/流程文档：`doc/` 目录（客户端开发先读这里）

---

## 1. 项目目标

实现一个基于 skynet 的 MMORPG 服务端框架（参考 bigworld 概念），并配一个 love2d 多客户端。重点是把框架层（`server/tinyworld`）与游戏业务层（`server/game`）严格分离。

---

## 2. 目录结构（当前）

```text
server/
  skynet/                       # skynet 引擎（不要改）
  lualib-src/                   # C 扩展源码：skiplist / timerwheel / recordstore
    Makefile                    # 编译输出到 ../luaclib
  luaclib/                      # 已编译的 .so（由 make -C lualib-src 生成）
  tinyworld/                    # 通用框架，不含具体游戏业务
    core/                       # class/json/proto/bin/service/event/util/mockdb/log/tag
    schema/                     # property / record / container / object / record_row / record_legacy
    entity/                     # entity / component / rpc / defs / entity_def
    framework/
      timer/
        timer_scheduler.lua     # 通用定时器调度器（cellapp 与 baseapp 可共用）
    net/
      msg.lua                   # message.log 格式化工具 + 协议编码入口
      protocol.lua              # 具体协议构造（object/prop/record/view/AUTH/ACCOUNT/RPC 信封）
    space/                      # space / cell_info（纯几何切分）
    combat/                     # ability / modifier / damage / combat_agent / projectile 等
    app/
      boot.lua                  # 框架启动入口
      registry.lua              # 服务地址注册表
      world/                    # world 服务 + server_space + load_balancer + cell_allocator
      login/                    # HTTP 登录服务
      gate/                     # 网关（连接/认证/转发/message.log）
      baseapp/                  # baseapp 服务 + baseentity + player_store
      cellapp/
        cellapp.lua             # cellapp 服务入口
        cell.lua                # 运行时 cell（tick/AOI/outbox/迁移/ghost）
        entities/               #   real_entity.lua / ghost_entity.lua
        components/             #   server_object.lua（cellapp 端组件）
        space/                  #   local_space.lua / spatial_index.lua
      db/ dbmgr/ logservice/
  game/                         # 游戏业务
    base/                       # baseapp 侧组件：bag / equipment / task / sync_stress(base)
    cell/                       # cellapp 侧组件：move / weather / sync_stress(cell)
    config/
      config                    # skynet 启动配置（真实 mysql，见第 4 节）
      init.lua                  # 配置聚合入口
      spaces.lua                # space 配置
      entity_defs.lua           # entity def 注册清单（base / cell）
      abilities.lua             # 技能数据目录配置
      player_template.lua       # 新角色/无存档默认模板
      schema.lua                # 建表 SQL / mock 数据
    def/                        # 对象定义（player/modifier/ability/container/projectile/server_object）
    scripts/npc/                # dota 风格 KV 数据（技能数值）
    scripts/vscripts/           # 技能/ modifier 脚本（只放业务逻辑）
    main.lua                    # 游戏启动钩子
  sql/init.sql                  # mysql 初始化脚本
  test/                         # 单元测试 + Python 客户端压测
    test/run_all.lua            # 全部单元测试入口
    test/test_projectile_10_clients.py
    test/test_projectile_live.py
client/                         # love2d 客户端（LÖVE/LuaJIT）
  main.lua
  src/                          # net/json/entities/views/records/ui/move/debuglog
doc/                            # 协议 / 登录流程 / 客户端开发指南
  README.md
  protocol.md
  login_flow.md
  client_dev_guide.md
  protocol_review.md
```

---

## 3. 当前代码关键设计

### 3.1 类型定义已统一

- 类一律用 `tinyworld.core.class`：
  - `class.makeClass("Xxx")` + `:ctor` + `Xxx.new(...)` 创建实例；
  - 子类用 `Base.extend("Sub")`。
- `Entity` / `Component` / `RealEntity` / `GhostEntity` / `BaseEntity` / `ServerObject` / combat 组件 / schema 类 / `TimerScheduler` / `SpatialIndex` / `EventBus` 均已统一。
- 纯工具模块仍为 `local M = {}`（无可实例化类型时）。
- 服务单例（cellapp/baseapp/gate/login/world/db/dbmgr/logservice 等）保持 `cmd` + `service.startService` 模式。

### 3.2 boot 启动顺序

`tinyworld/app/boot.lua` 负责框架启动：

```
registry -> logservice -> dbmgr -> world -> login
-> baseapp(s) -> gate(s) -> cellapp(s)
-> world.create_space("main")
-> game.main.start(registry)
```

服务地址统一通过 `registry` 注册/查询，各服务在 init 时查询并缓存。

### 3.3 world / space / cellapp

- `game.config.spaces` 只描述空间几何和感知参数（aoiRange / ghostRange / cellSize / 手动 cells）。cellapp 由 world 在 `create_space` 时运行时分配。
- `SpaceConfig.compile(def)` 只做几何切分（自动或手动）。
- `CellAllocator.distribute(config, appIds)` 把 cell 轮询分配给 cellapp。
- `ServerSpace` 是 world 侧空间运行态；`LocalSpace` 是某一个 space 在某 cellapp 上的运行态。
- `Cell` 是运行时 cell。每个 tick 顺序：
  ```
  updateEntities -> syncAoi -> updateVisibilities
  -> buildOutboxes -> deliverOutboxes
  -> checkMigrations -> ensureGhosts -> broadcastGhostChanges
  -> updateTimers
  ```

### 3.4 协议层（重要，最近重构）

- 帧格式：`2 字节小端长度 + JSON 负载`。见 `tinyworld/core/proto.lua`。
- 具体消息构造统一在 `tinyworld/net/protocol.lua`：
  - `make / account / authOk / authFail / rpc`
  - `objectAddMsg / objectRemoveMsg / objectAddSelf / entitySpawnInfo / clientProps`
  - `propMsg / recordMsg / viewMsg`
- `tinyworld/net/msg.lua` 只保留 message.log 格式化与 `encodeBody`。
- 完整协议说明：`doc/protocol.md`。

### 3.5 登录 / 退出 / 重登录

- 流程：HTTP `/login` → `AUTH auth` → `ACCOUNT characterList` →（可选 `createCharacter`）→ `ACCOUNT selectCharacter` → `object add(isSelf)` 进入世界。
- 会话管理在 baseapp：
  - `sessions[connId]` 与 `playerSessions[playerId]` 双索引；
  - 同账号重复登录会顶替旧连接；
  - 退出/断线用 `teardownEntity`（幂等）统一处理：取 cell 坐标 → `cellapp.despawn_entity` 销毁 real → 存盘 → `entity:teardown()`。
- cellapp 提供 `cmd.despawn_entity(spaceId, cellKey, entityId)`，负责销毁 real（触发 onDestroy、清理 ghost、移出 cell）。
- gate 对所有 connect/disconnect 写日志，并保证 connect→disconnect 配对。
- 详细流程与状态机：`doc/login_flow.md`。

### 3.6 entity / schema

- `Entity` 基类：`props / records / containers / rpc / components / event`。
- schema 属性只通过 `entity:set` / `entity.field = value` 写；不要 rawset schema 字段。
- `RealEntity` 与 `GhostEntity` 是固定设计，不要合并。
- 迁移与 ghost 判定分离：
  - `Entity:canMigrate()`：`def.migratable=false` 时 false（只影响跨 cell 迁移）。
  - `Entity:canGhost()`：`def.ghostable=false` 时 false（只影响是否给其他 cell 创建 ghost）。
  - real 销毁时 `RealEntity:onDestroy` 会 `Cell:destroyGhostsOf(real)`；迁移走 reparent，不销毁。
- `Record`：
  - C 扩展路径：`lualib-src/recordstore.c`（`recordstore.define` 在启动阶段按类名共享 desc，`recordstore.new` 创建实例）。C 不可用时回退 `record_legacy.lua`。
  - `Record.define(def)` 必须在启动阶段（`entity_def.lua` 的 `defineRecordStructs`）显式注册。`Record.new` 只查询不惰性注册。
- `Container` 子对象统一用 `Object`（`tinyworld/schema/object.lua`）承载 props/records。
- `record_row.lua` 是 legacy 行对象（Row 的 Lua 版），C 路径下由 recordstore 提供行对象。

### 3.7 定时器

- 通用时间轮：`tinyworld/framework/timer/timer_scheduler.lua`（C 扩展 `timerwheel.so`；单位毫秒）。
- `TimerScheduler:update(deltaSec)` 每帧一次 `wheel:update(math.floor(deltaSec*1000))`，不做 1ms 步进。
- `TimerScheduler:add(entity, delaySec, times, fn)`：delaySec 秒；`times=-1` 无限。
- Cell 挂载：`Cell:addTimer / removeTimer / updateTimers`。

### 3.8 combat

当前 combat 模块：

- `tinyworld/combat/ability.lua`：Ability 类
- `tinyworld/combat/modifier.lua`：Modifier 类
- `tinyworld/combat/damage.lua`：伤害/治疗结算，支持 ghost 目标路由到 real
- `tinyworld/combat/modifier_manager.lua`：add/remove/hasModifier
- `tinyworld/combat/ability_loader.lua`：扫描 vscripts 并注册 abilityFactory
- `tinyworld/combat/combat_agent.lua`：战斗组件（技能装配、事件 RPC、ghost→real 结算入口）
- `tinyworld/combat/projectile.lua`：投掷物运动/命中组件
- `tinyworld/combat/projectile_manager.lua`：投掷物创建工具
- `tinyworld/combat/env.lua`：共享逻辑环境（IsServer）

### 3.9 游戏业务目录

- baseapp 侧组件在 `game/base/`：bag / equipment / task / sync_stress(base)
- cellapp 侧组件在 `game/cell/`：move / weather / sync_stress(cell)
- def 目录不变：`game/def/...`
- `sync_stress` 已拆成 base/cell 两个文件；除非显式配置否则不会加载。

---

## 4. 启动 / 测试

### 4.1 编译 C 扩展

```bash
cd /root/test/testv3/server
make -C lualib-src clean && make -C lualib-src
```

生成 `luaclib/skiplist.so`、`luaclib/timerwheel.so`、`luaclib/recordstore.so`。

C 模块用 `skynet/3rd/lua` 头文件编译（详情见 Makefile）。  
单元测试请在 `skynet/3rd/lua/lua`（Lua 5.5）解释器下跑，并设置 `LUA_CPATH='./luaclib/?.so;;'`，否则 C 扩展无法加载。

### 4.2 启动服务器（真实 mysql）

```bash
cd /root/test/testv3/server
./skynet/skynet game/config/config
```

服务端口：game 8000、login HTTP 8080。  
mysql 连接信息在 `game/config/config`：`127.0.0.1:3306` 数据库 `tinyworld`，账号 root，无密码。  
当前数据库有 10 个账号 test1~test10（密码 123456）、10 个玩家角色。

启动后日志会看到：

```
db connected 127.0.0.1:3306
login http listening on 8080
gate 1 listening on 8000
tinyworld bootstrap done
```

### 4.3 单元测试

```bash
cd /root/test/testv3/server
LUA_CPATH='./luaclib/?.so;;' skynet/3rd/lua/lua test/run_all.lua
```

应输出 `ALL TESTS PASS`。

> 说明：测试用 Lua 5.5（`skynet/3rd/lua/lua`）。系统自带 `lua5.4` 无法加载 C 扩展（ABI 不匹配），只适合纯 Lua 调试。

### 4.4 客户端压力测试（真实服务器）

```bash
cd /root/test/testv3/server
python3 test/test_projectile_live.py
python3 test/test_projectile_10_clients.py
```

运行前确保服务器已启动、mysql 已就绪。测试会打开真实登录 + 协议收发。

---

## 5. 当前服务器状态

- 服务器已启动并运行中（`./skynet/skynet game/config/config`）。
- 日志：`/tmp/skynet_server_runtime.log`。
- message.log：`server/game/logs/message.log`。
- mysql：`tinyworld` 数据库，10 账号 / 10 角色 / 10 player_bin。

---

## 6. 强约束 / 约定（沿用）

- 文件名小写；函数/方法名 camelCase；服务命令小写下划线。
- 通用代码放 `server/tinyworld`，游戏业务放 `server/game`。
- 类型定义统一用 `tinyworld.core.class`，不要回归手写 `X = {}; X.__index = X`。
- 协议构造统一走 `tinyworld/net/protocol.lua`，不要再散落 `{t=..., n=...}`。
- RealEntity/GhostEntity 是固定设计。
- 不要用 `goto`。
- 不要 rawset schema 字段。
- `sync_stress` 是压力测试组件，不要默认加载。
- **关键依赖字段不允许用 `or fallback` 静默吞 nil**（如 `runtime`、`cell`、`space`、`source`、`config`）。缺失必须 `assert` 显式失败或输出错误日志。
- 可选配置可以带注释的默认值；可选回调用显式 `if` 判断。
- **禁止无意义布尔规范化**：不写 `not not x`、`x and true or false` 等；需要布尔契约直接 `== true` / `== false`，或 `assert(type(v) == "boolean")`。
- C skiplist 保持 Redis 原版内核（允许重复节点），唯一性由上层 `spatial_index.lua` 保证（enter/move/leave 先删后插）。

---

## 7. 当前正在进行 / 下一步

1. **客户端的完整开发**（另一个会话正在进行）：
   - 目标：独立客户端完整登录 → 选角色 → 进入世界 → 游玩（移动/背包/装备/任务/技能）。
   - 先读 `doc/README.md`、`doc/protocol.md`、`doc/login_flow.md`、`doc/client_dev_guide.md`。
   - 已知阻塞点（详细见 `doc/protocol_review.md`）：目前协议只同步运行时状态，**没有静态配置/资源加载协议**（物品表、技能数值、modifier 详情、任务文本、资源映射、时间同步等）。这些是下一步服务端需要补齐的方向，当前先不要处理。

2. 服务端后续可能的工作（尚未开始）：
   - 设计 `CONFIG / RESOURCE / SYSTEM` 静态配置下发协议。
   - 扩展 `createCharacter` 支持外观/职业/初始属性。
   - 显式 `snapshot` 标志区分全量/增量同步。

---

## 8. 提示词（新会话使用）

### 客户端开发会话（当前重点）

```text
请阅读 /root/test/testv3/PROJECT_HANDOFF.md 和 /root/test/testv3/doc/ 目录下的协议文档。
服务端已经启动，实际地址：
- 登录 HTTP：http://127.0.0.1:8080/login?name=test1&password=123456
- 游戏 TCP：127.0.0.1:8000
- 测试账号：test1~test10，密码 123456
实现一个客户端，完成登录 → 拉角色 → 选择角色 → 进入世界 → 收取 object/record/view/prop/RPC 消息，
并支持移动 RPC 与简单背包/任务/技能 UI。服务器真实 mysql 已就绪，可直接联调。
请严格按 doc/protocol.md 的帧格式（2 字节小端长度 + JSON）实现。
```

### 服务端后续会话（未开始）

```text
请阅读 /root/test/testv3/PROJECT_HANDOFF.md，按文档理解 tinyWorld。
当前任务：设计并实现静态配置下发协议（CONFIG/RESOURCE/SYSTEM），
参考 doc/protocol_review.md 的缺口分析，先给出方案再实现，最后跑单测和登录联调。
```
