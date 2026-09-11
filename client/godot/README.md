# tinyWorld Godot 客户端

Godot 4.x（GDScript）实现的 2D MMORPG 客户端，对接 skynet 服务器协议：
**TCP 明文 + 2 字节小端长度帧 + JSON 信封 `{t, n, d}`**（见 [`doc/protocol.md`](../../doc/protocol.md)）。

## 分层架构

依赖**单向**：上层可依赖下层，下层不知道上层。新增功能按职责放进对应层。

```
client/godot/
├── project.godot            # 项目配置(主场景 scenes/main.tscn)
├── scenes/
│   └── main.tscn            # 主场景
├── scripts/
│   └── main.gd              # 入口: 装配各层 + 输入 + 主循环(不含业务细节)
│
├── core/                    # ---- 框架层: 与玩法无关 ----
│   ├── protocol/
│   │   └── protocol.gd      #   协议常量与消息构造(与 server/tinyworld/net/protocol.lua 对齐)
│   └── net/
│       ├── frame_codec.gd   #   帧编解码: 2 字节小端长度 + JSON(纯函数, 可单测)
│       ├── tcp_client.gd    #   TCP 连接/收发/切帧/断线信号
│       └── http_login.gd    #   登录 HTTP: GET /login
│
├── game/                    # ---- 玩法层: 状态与规则 ----
│   ├── session/
│   │   └── login_flow.gd    #   登录状态机: HTTP->AUTH->characterList->selectCharacter->WORLD
│   ├── world/
│   │   ├── entity.gd        #   实体数据(属性快照 + 服务器确认序号)
│   │   ├── world_state.gd   #   世界状态总入口, 消费 object/prop/record/view
│   │   ├── record_store.gd  #   record 表格增量(add/remove/set)
│   │   └── view_store.gd    #   view 容器增量(add/remove/set/view)
│   └── movement/
│       └── predictor.gd     #   移动本地预测 + 服务器 Reconciliation
│
├── ui/                      # ---- 表现层: 渲染与交互 ----
│   ├── hud/
│   │   ├── hud.gd           #   HUD 容器: 状态行 + 日志 + 面板
│   │   └── panels/
│   │       ├── panel_base.gd       # 面板基类(单行 Label)
│   │       ├── player_panel.gd     # 自身属性
│   │       ├── bag_panel.gd        # 背包 (view: bag)
│   │       ├── equipment_panel.gd  # 装备 (view: equipment)
│   │       ├── task_panel.gd       # 任务 (record: current_tasks)
│   │       ├── ability_panel.gd    # 技能 (view: abilities_view)
│   │       └── modifier_panel.gd   # Buff  (view: modifiers_view)
│   ├── world/
│   │   ├── world_grid.gd    #   世界网格背景(移动参照)
│   │   ├── entity_view.gd   #   实体显示层(entityId -> ActorNode, 他人位置插值)
│   │   ├── actor_node.gd    #   角色表现: 序列帧播放 + 朝向 + 占位回退
│   │   └── sprite_sheet.gd  #   序列帧表加载器(JSON 描述 -> SpriteFrames)
│   └── combat/
│       └── combat_fx.gd     #   战斗飘字(伤害/治疗)
│
├── assets/
│   └── sprites/             #   角色序列帧(hero.png/json + 规范说明)
│       ├── README.md        #   ★ 美术规范: 帧表布局 / 描述文件 / 朝向规则
│       ├── hero.png         #   占位序列帧(脚本生成, 4 向 x 3 动作)
│       ├── hero.json        #   序列帧描述文件
│       └── gen_placeholder_sheet.py
├── test/
│   ├── test_direction_parity.gd    # 与服务端 direction.lua 对拍(1441 采样点)
│   ├── test_facing_mapping.gd      # dir -> 4 向 -> 美术行 的映射验证
│   └── lua_ref.txt                 # 对拍用的服务端参考数据
└── .gitignore               # 忽略 .godot/ 缓存
```

### 朝向数据流

```
服务端 Move:onTick                     客户端
  set("dir", math.atan(dy,dx))  ──▶  object add 的 props.dir(全量)/ prop props 的 d.dir(增量)
  (sync="all" 自动下发)                    │
                                          ▼
                                Direction.quantize(dir)   连续角度 -> 4 向(RIGHT/DOWN/LEFT/UP)
                                          │
                                          ▼
                                Facing.render_for(4向, directions)  -> 美术行 + 是否翻转
                                          │
                                          ▼
                                ActorNode 播放 "<动作>_<朝向>"
```

**自己**用输入方向立即预测朝向（转向无延迟），服务器 `prop` 回来后以服务端值为准；
**他人**直接用同步来的 `dir`。美术支持 4 行（独立绘制）或 3 行（+镜像）两种布局，见
[`assets/sprites/README.md`](assets/sprites/README.md)。

### 各层职责边界

| 层 | 可以做 | 不可以做 |
|----|--------|----------|
| `core/` | 协议常量、编解码、socket/HTTP | 引用 `game/` 或 `ui/` |
| `game/` | 维护状态、状态机、发信号 | 直接操作节点/绘制 |
| `ui/` | 绘制、读 `WorldState` 渲染 | 直接收发网络消息 |
| `main.gd` | 创建实例、连信号、转发 | 写业务规则 |

**依赖注入**：各模块由 `main.gd` 显式创建并互相连接，**不使用 autoload 全局单例**，
使依赖关系可见、可测试（`FrameCodec` / `MovePredictor` 等纯逻辑可直接单测）。

## 运行

前置：服务器已启动（登录 8080 / 游戏 8000）。

用 Godot 4.x 打开本目录（`client/godot/`），运行主场景即可。

命令行参数（可选）：

```bash
godot --path client/godot -- --account=test2 --host=127.0.0.1
godot --path client/godot -- --account=test1 --auto-move --cast --auto-quit=10
```

| 参数 | 说明 |
|------|------|
| `--account=NAME` | 登录账号（test1~test10，密码 123456） |
| `--host=IP` | 服务器地址，默认 127.0.0.1 |
| `--auto-move` | 自动向右移动（验证移动 + Reconciliation） |
| `--cast` | 自动对最近实体施法（验证战斗事件） |
| `--auto-quit=N` | N 秒后自动退出（无人值守验证用） |

## 操作

| 按键 | 功能 |
|------|------|
| WASD / 方向键 | 移动（本地预测 + 服务器 Reconciliation） |
| `1`~`8` | 施放第 N 个技能（自动选最近目标） |
| 鼠标左键 | 点地面/角色，对最近目标施放技能 1 |
| `T` | 接任务 `onAcceptTask`（taskid 自增） |
| `R` | 重连 |

## 已实现

- **登录**：HTTP 登录 → 连接 gate → `AUTH auth` → `characterList` → `selectCharacter` → 进入世界（`object add` 且 `isSelf=true`）。
- **世界同步**：`object add/remove`、`prop props`（含 `seq`）、`record`（current_tasks）、`view`（bag / equipment / abilities_view / modifiers_view）。
- **移动**：`onRequestMove{seq,dt,dirX,dirY}` + 本地预测 + 服务器 `seq` Reconciliation；`onStopMove`。
- **任务**：`onAcceptTask` → 收到 `record current_tasks` 的 add op。
- **战斗**：`onCastAbility` → `onCombatDamage` / `onCombatHeal` 飘字表现；`onSpellCast` 触发攻击动作。
- **角色表现**：序列帧播放（站立/行走/攻击 × 4 朝向）；服务端 `dir` 连续角度 → 客户端量化到
  4 向选帧；自己本地预测转向、他人用同步 `dir`；无美术资源时自动回退到带朝向箭头的占位绘制。
  见 [`assets/sprites/README.md`](assets/sprites/README.md)。
- **退出/断线**：清理本地状态，可重连；服务器 `message.log` 每连接 connect/disconnect 配对。

## 开发须知

- **不要用 `get` / `disconnect` / `is_connected` 等 Godot 原生方法名**命名自己的函数
  （`Object` 已有这些方法，会触发 "overrides a method from native class" 编译错误）。
  本项目用 `get_view()` / `get_rows()` / `close()` 等名字规避。
- **新增数据面板**：继承 `PanelBase` 实现 `_build_text()`，在 `hud.gd` 里注册即可。
- **新增协议消息**：常量加到 `core/protocol/protocol.gd`；世界同步类消息在
  `WorldState.apply_message()` 里分发；RPC 事件在 `main.gd._on_rpc()` 里处理。
- **换角色美术**：只改 `assets/sprites/hero.png` + `hero.json`，**不用改代码**。
  布局规范见 [`assets/sprites/README.md`](assets/sprites/README.md)。
- 服务器**不下发静态配置**（物品名/技能描述/图标等），客户端只显示运行时同步到的
  `itemId` / `taskid` / 技能 id 等数字（见 [`doc/protocol_review.md`](../../doc/protocol_review.md) 已知缺口）。
- 坐标单位与服务器一致（世界单位，非像素）。
