# tinyWorld 项目交接文档（给新 AI 会话使用）

## 目标

读懂本仓库并继续开发/优化 tinyWorld：一个基于 skynet 的 MMORPG 服务端框架（参考 bigworld 概念），
以及一个 love2d 客户端。文档覆盖：
- 项目布局
- 核心架构与数据流
- 关键设计约束
- 如何验证
- 已知待办与“不要做什么”
- 继续开发的建议入口

---

## 1. 项目布局

```text
server/
  skynet/                       # skynet 引擎(按 cservice/lualib/luaclib 存在)
  tinyworld/                    # 通用框架（不含具体游戏业务）
    core/                       # class/log/json/proto/bin/service/event/util/mockdb
    schema/                     # property/property_schema/record/record_def/container/container_def/child_object
    entity/                     # entity/component/rpc/defs/entity_def
    net/                        # msg 协议封装 & message.log 格式化
    space/                      # cell_info/space
    combat/                     # env/ability/modifier/unit/combat/damage/sync
    app/
      world/                    # world 服务 + server_space + load_balancer
      cellapp/                  # cellapp 服务 + local_space + cell + aoi + real/ghost entity + entity_msg
      baseapp/                  # baseapp 服务 + baseentity
      gate/
      login/
      dbmgr/
      db/
      logservice/
  game/                         # 游戏业务（不进入 tinyworld 通用层）
    def/                        # 对象定义目录（每类对象一个目录）
      player/
      modifier/
      ability/
      container/
    components/                 # move/bag/equipment/task/weather/combat_agent/sync_stress
                                # sync_stress 是压力测试组件
    config/                     # skynet config + spaces + schema.sql
    scripts/
      npc/                      # dota 风格 KV 数据
      vscripts/                 # dota 风格技能脚本
    init.lua                    # 游戏挂载点：注册 defs、load/save、setup 组件
  sql/                          # 建表 sql
  test/                         # 测试
client/
  main.lua
  src/                          # net/json/entities/views/records/ui/move/debuglog
PROJECT_HANDOFF.md              # 本文件
```

## 2. 核心概念

### 2.1 三类数据布局

每个对象（player/monster/modifier/ability/container/子对象）都由定义文件描述：
- `props`：属性（`PropertySchema`）
- `records`：表格（`Record`）
- `containers`：容器/视图（`Container`）

`props` 字段可包含：`name/type/sync/persist/comment/default`。
`sync` 取值：`none/self/all`。

容器定义结构：
```lua
return {
  name = "bag",
  persist = true,
  props = { ... },        -- 容器自身属性
  records = { ... },      -- 容器自身表格
  childDef = { props = { ... }, records = { ... } },  -- 子对象定义（与 player 同结构）
}
```
**不再使用**：`viewProps`、`childProps`、`childRecords`、`setViewProp`、`getViewProp`、
`setChildProp`、`getChildProp`、`getChildRecord`。

### 2.2 数据读写方式

属性：
```lua
entity.level = 10
entity:set("level", 10)
```
`entity` 的属性 table（`entity.props`）负责 dure/同步；不要直接用 `entity.x =`（某些 x/y 由 real entity rawset）。

表格（Record）：
```lua
local tasks = entity:getRecord("current_tasks")
tasks:add({ taskid = 11, state = 0, progress = 0 })
local row = tasks[10]       -- 读行
row.progress = row.progress + 1   -- 行属性写回自动同步
tasks:remove(10)
```
`Record` 行是 `ChildObject`，字段写回会自动触发同步 op。

容器（View）：
```lua
local bag = entity:getContainer("bag")
bag:openView("bag")
bag:add({ id = 1, itemId = 1001, count = 3 })
local item = bag:get(1)
item.count = item.count + 1  -- 直接改子对象属性
bag:remove(1)
```
容器自身属性：
```lua
bag.capacity = 16 -- 直接写
```

### 2.3 实体同步模型（Real/Ghost 与 cell）

一个 cell 内有两种实体：
- `RealEntity`：真身，只有 home cell 保存权威对象
- `GhostEntity`：别的 cell 中 real 的投影

用一个统一的 `outbox` 思路：
1. `Cell:tick` 分成 `updateEntities` / `updateVisibilities` / `buildOutboxes` / `deliverOutboxes`
2. 每个 entity 在一次 buildOutbox 中只打包一次变更
3. 观察者视角：从 `player.visibleEntities` 中取对象 outbox，发给自己
4. `Real` 的 outbox 通过 `real:sendGhostEach(real.outbox)` 同步给所有 ghost
5. ghost 下一 tick 再像 real 一样打包给观察者

ghost 协议入口位于 `cellapp.lua` 的 `cmd.ghost_*`，最终落到 `Cell` 方法：
- `upsertRemoteGhost`
- `promoteGhost`
- `applyRemoteGhostSync`
- `destroyRemoteGhost`

`LocalSpace` 已经尽量薄：只管理本 cellapp 的 cell 集合与 space 数据边界。
不要把迁移策略/实体物化逻辑写回 LocalSpace。

## 3. 服务与启动

`server/game/config/config` 指定：
- `cellapp_count=2`、`baseapp_count=1`
- `db_mode=mysql`，也支持 `mock`
- `login_port=8080`、`gate_ports=8000`

启动：
```bash
cd /root/test/testv3/server
./skynet/skynet game/config/config
```

服务名：
- `world`：space/cell 管理，保存完整 space 信息
- `cellapp`：运行 cell
- `baseapp`：玩家与 base entity
- `login`：http 登录鉴权
- `gate`：socket/gateway
- `dbmgr`：db 服务负载均衡
- `db`：mysql/mock 执行 sql
- `logservice`：写 message.log

服务入口命令用小写下划线，例如 `spawn_entity`、`ghost_create`、`cellapp_register`。
所有服务必须有一个 `init` 方法（由 bootstrap/main 逐一切线/调用或内部 init）。

## 4. 战斗 / vscripts

vscripts 目录遵循 dota2 风格：
- NPC 数据在 `game/scripts/npc/...`
- 技能文件 `game/scripts/vscripts/heroes/...`
- 文件只放具体技能逻辑.
- 技能脚本直接定义全局 `ability_...`/`modifier_...`（不要 `local M` 包裹）
- `LinkLuaModifier` 是 vscripts 预加载入口，能力创建时预加载 `ScriptFile`

技能加载：
- 玩家技能列表取自 baseentity 的 `records.abilities`，由 baseapp 打包成 `initData`
- cellapp 创建 cell entity（real）时通过 `CombatAgent` 的 `entity:loadAbilities(names)` 创建能力
- 被动 modifier 通过 ability 的 `GetIntrinsicModifierName()` 返回 name，由 `Ability:initModifier()` 自动挂载

modifier/ability 状态同步：
- `modifiers_view`（观测者可见）：cell 上 View，子对象是 `modifier_def`
- `abilities_view`（selfOnly）：cell 上 View，子对象是 `ability_def`
- combat 同步字段由 `modifier:viewData()` / `ability:viewData()` 提供；通用层只负责 view 增删改

## 5. 协议

网络包：2 字节小端长度 + JSON body。

消息：
- 属性：`prop props{entityId, ...}`
- 对象：`object add{entityId, kind, props, modifiers}` / `object remove{entityId}`
- 表格：`record name{entityId, ops}`
- 视图/容器：`view name{entityId, ops}`（op：add/remove/set/view）
- 一次性战斗事件：`RPC onCombatDamage/onCombatHeal/onSpellCast`
  - modifier 的 add/remove/refresh 不再单独发 RPC，只走 view

## 6. 测试与验证

```bash
cd /root/test/testv3
 或做 server/ 下# 或做 server/ 下
```

已有测试：
- property/record/container/entity/bin
- space 迁移/ghost
- load_balancer
- combat/skills

真实多客户端验证可以用 python 模拟协议，也可以启动 love 客户端。
love 需要 xvfb（本环境已安装）。

## 7. 设计约束/不要做

- 文件名小写，服务路径小写。
- 函数/类型 camelCase；对象类用 `class.makeClass`，模块单类时直接 `return Class`。
- 不要用 `goto`。
- 不要把业务写进 tinyworld；tinyworld 是通用框架。
- 不要打印大段代码；函数简洁、早 return、避免嵌套。
- 老的 `viewProps/childProps/setChildProp` 等已废弃，不要新增/恢复。
- role-merge（同一 CellEntity 复用为 real/ghost）暂时放弃，后续明确要求再做。
- `playerId` 作为玩家 cell entityId；monster/projectile 用 `nextId()`。

## 8. 当前状态

- mysql 模式可运行
- 登录/进世界/移动同步/背包装备任务同步/战斗同步均验证通过
- 大量测试覆盖
- `Cell:buildOutboxes/deliverOutboxes` 同步模型已整理
- 旧 RPC 同步已清理，modifier 使用 View 同步
- message.log 毫秒级

## 9. 建议继续开发方向

1. 彻底合并 RealEntity / GhostEntity 为统一 CellEntity role 对象（之前暂停）
2. 完善 baseapp 时长/组件 tick 的生命周期与 player 下线保存
3. 客户端接入 vscripts/IsServer 共享逻辑
4. 技能 index 改为 abilityName 驱动，避免顺序依赖
5. 增强 AOI 网格与跨 cell 推送验证

## 10. 新会话提示词

将以下内容发给新 AI 会话：

---

请阅读 /root/test/testv3/PROJECT_HANDOFF.md。
按文档理解 tinyWorld 项目。遵循文档中的设计约束，不要恢复已废弃的 viewProps/childProps/setChildProp 等旧接口。
先跑 `cd /root/test/testv3/server && lua test/run_all.lua` 确认基线，再告诉我你理解的核心架构和下一步建议。不要动代码，只读代码、跑测试、报告理解。
---
