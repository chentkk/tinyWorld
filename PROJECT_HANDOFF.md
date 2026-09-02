# tinyWorld 交接文档

本仓库当前位于 `/root/test/testv3`。服务器在 `/root/test/testv3/server`，客户端在 `/root/test/testv3/client`。

## 1. 项目目标

实现一个基于 skynet 的 MMORPG 服务端框架（参考 bigworld 概念），并配一个 love2d 多客户端。重点是把框架层（`server/tinyworld`）与游戏业务层（`server/game`）严格分离。

## 2. 目录结构

```text
server/
  skynet/                       # skynet 引擎（不要改）
  tinyworld/                    # 通用框架，不含具体游戏业务
    core/                       # class/json/proto/bin/service/event/util/mockdb/log
    schema/                     # 属性/表格/容器/子对象
    entity/                     # Entity / Component / RPC / def 注册
    net/                        # 协议消息构造与 message.log 格式化
    space/                      # SpaceConfig / CellInfo
    combat/                     # 战斗框架
    app/
      boot.lua                  # 框架启动入口
      registry.lua              # 服务地址注册表
      logservice/ db/ dbmgr/ world/ login/ baseapp/ gate/ cellapp/
  game/                         # 游戏业务
    config/
      config                    # skynet 启动配置
      init.lua                  # 配置聚合入口
      spaces.lua                # space 配置
      entity_defs.lua           # entity def 注册清单
      abilities.lua             # skill 数据目录配置
      player_template.lua       # 玩家默认模板
      schema.lua                # 建表 SQL / mock 数据
    def/                        # 对象定义（player/modifier/ability/container/projectile）
    components/                 # 游戏业务组件（bag/equipment/task/move/weather/sync_stress）
    scripts/npc/                # dota 风格 KV 数据
    scripts/vscripts/           # 具体技能/ modifier 脚本（只放业务逻辑）
    main.lua                    # 游戏启动钩子（目前无额外游戏服务）
  sql/init.sql                  # mysql 初始化脚本
  test/                         # 测试
client/
  main.lua
  src/                          # net/json/entities/views/records/ui/move/debuglog
```

## 3. 核心设计

### 3.1 boot 启动顺序（fixed）

`tinyworld/app/boot.lua` 负责框架启动：

```
registry -> logservice -> dbmgr -> world -> login
-> baseapp(s) -> gate(s) -> cellapp(s)
-> world.create_space("main")
-> game.main.start(registry)
```

- 所有框架服务由 boot 显式 `init`；
- 服务地址统一在 `registry` 服务注册/查询；
- 底层服务地址不会动态变化，服务在 init 时查询一次并缓存；
- `skynet.setenv` 不再放服务地址，只保留 boot 静态参数。

### 3.2 world / space / cellapp

- `world` 是分布式场景管理中心；
- `game.config.spaces` 只描述空间几何和感知参数，不描述 cellapp；
- `world.create_space(spaceId)`：
  1. 读 `game.config.spaces` 中的 def；
  2. `SpaceConfig.compile(def)` 只做切分；
  3. `CellAllocator.distribute(config, appIds)` 按顺序轮询分配 cellapp；
  4. 存 `ServerSpace`；
  5. 给每个 cellapp `bind_cells`（含完整 `cellId -> appId` 映射）；
- `SpaceConfig.compile` 支持：
  - 自动切分：`cellSize` 或 `cellCols/cellRows`
  - 手动切分：`cells = { {id,x,y,w,h}, ... }`
- **ghostRange 建议为 `2 * aoiRange`**，确保相邻 cell 边缘可见性安全。
- `LocalSpace` 是一个 space 在某个 cellapp 上的运行态；一个 cellapp 可运行多个 space。
- `Cell` 是运行时 cell，含 entities/players/AOI，tick 顺序：
  ```
  updateEntities -> syncAoi -> updateVisibilities
  -> buildOutboxes -> deliverOutboxes
  -> checkMigrations -> ensureGhosts -> broadcastGhostChanges
  ```

### 3.3 entity / schema

- `Entity` 基类：`props / records / containers / rpc / components / event`
- 属性同步约定：**schema 字段只通过 `entity:set` / `entity.field = value` 写；绝不允许 rawset，否则 `Entity:__index` 在读时直接报错**
- `RealEntity` 与 `GhostEntity` 是固定设计，不要合并或统一。
- `Record` 与 `Container` 都在一个 flush 周期内把同一行/同一子对象的多次 `set` 合并成一个 op。
- `Container` 子对象现在统一用 `Object`（`tinyworld/schema/object.lua`）承载 props/records；`child_object.lua` 已简化并重命名为 `record_row.lua`。

### 3.4 combat

当前 combat 模块：

- `tinyworld/combat/ability.lua`：Ability 类
- `tinyworld/combat/modifier.lua`：Modifier 类
- `tinyworld/combat/damage.lua`：伤害/治疗结算，并支持 ghost 目标路由到 real
- `tinyworld/combat/modifier_manager.lua`：add/remove/hasModifier
- `tinyworld/combat/ability_loader.lua`：自动扫描 vscripts 并注册 abilityFactory
- `tinyworld/combat/combat_agent.lua`：完整战斗组件（技能装配、驱动、事件 RPC、ghost→real 结算 RPC 入口）
- `tinyworld/combat/projectile.lua`：投掷物运动/命中组件
- `tinyworld/combat/projectile_manager.lua`：追踪/直线投掷物创建工具
- `tinyworld/combat/env.lua`：共享逻辑环境（IsServer）
- `tinyworld/app/cellapp/`：不再有 `combat_sync/settlement`；战斗事务统一归 `CombatAgent`

### 3.5 同步链路

```
Cell:tick
  -> entity onTick 改 props/records/containers
  -> AOI 重对齐
  -> 玩家可见性更新
  -> buildOutbox（每个实体一次）
  -> deliverOutboxes（观察者领取）
  -> 迁移/ ghost / ghost 变更广播
```

- Real 的 outbox 会发给它的 ghost；
- Ghost 下一 tick 与 real 一样统一打包给观察者；
- spawn / object add 之后会清理初始 dirty，避免同 tick 重复 prop；
- object add 不再携带历史 `modifiers` 字段；modifier 状态只通过 `modifiers_view` 同步。

### 3.6 投掷物 projectile

- 定义：`game/def/projectile/projectile_def.lua`
- 组件：`tinyworld/combat/projectile.lua`
- 创建工具：`tinyworld/combat/projectile_manager.lua`
- cmd：`cellapp.spawn_projectile` 等同于 `spawn_entity`，kind 默认 `Projectile`
- `projectile` 支持：
  - `targetId` 存在：追踪目标，命中即销毁；
  - 无 `targetId`：直线前进；
  - `pierce=false` 命中销毁，`pierce=true` 穿透到超距或 `maxHits`;
  - 默认直线 `pierce=true`;
  - 同一 realId 只命中一次去重；
- 投掷物 `def.migratable=false`，不做跨 cell 迁移；
- 跨 cellapp 目标通过 ghost 机制 + `dealDamage` 的 ghost→real 路由完成结算。

## 4. 已固定的关键命令/约束

- 文件名小写；函数/方法名 camelCase；服务命令小写下划线；
- 通用代码放 `server/tinyworld`，游戏业务放 `server/game`；
- 旧接口 `viewProps/childProps/childRecords/setViewProp/getViewProp/setChildProp/getChildProp/getChildRecord` 已废弃，禁止恢复；
- RealEntity/GhostEntity 是固定设计；
- 不要用 `goto`；
- 不要直接 rawset schema 字段；
- `sync_stress` 是压力测试组件，当前不要默认加载。

## 5. 测试

```bash
cd /root/test/testv3/server
lua test/run_all.lua
```

应输出 `ALL TESTS PASS`。

关键测试文件：
- `test/run_all.lua`
- `test/test_projectile_10_clients.py`：10 客户端投掷物压测（需真实服务器/DB 准备）

## 6. 下个会话必做任务

1. 把 space 拆为 4 个 cell，并配置 4 个 cellapp；
2. 准备 10 个测试账号/角色，出生在 space 中心附近（4 个 cell 交界处），使每个玩家可能在其他 3 个 cell 都有 ghost；
3. 运行 10 客户端测试，让其中 1 个施放投掷物技能；
4. 比对 `server/game/logs/message.log`，检查：
   - 10 个客户端是否都登录/进入世界；
   - 远端 ghost 是否创建/同步；
   - projectile object add / 移动 prop / object remove 是否正常；
   - 每个目标是否只结算一次，是否广播给所有观察者；
   - message.log 格式是否符合预期。

## 7. 提示词（下个会话直接使用）

```text
请阅读 /root/test/testv3/PROJECT_HANDOFF.md，按文档理解 tinyWorld。
然后执行任务：
1. 启动 mysql 并准备测试数据。
2. 启动服务器（4 cellapp / 2x2 space）。
3. 运行 10 客户端投掷物压力测试。
4. 比对 server/game/logs/message.log，报告是否符合预期。
不要修改任何代码。
```
