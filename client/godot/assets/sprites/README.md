# 角色序列帧资源规范

## 当前状态

`hero.png` 是**占位美术**（脚本生成的色块小人），用于在没有正式美术时跑通并验证
"加载 → 切帧 → 朝向选择 → 动作切换"整条管线。正式美术到位后按同样布局替换即可，**不用改任何代码**。

重新生成占位图：

```bash
python assets/sprites/gen_placeholder_sheet.py
```

## 帧表布局

一张 sheet，**行 = 朝向，列 = 帧序号**：

```
                col0  col1  col2  col3  col4  col5
  row0-3   idle    ┌─────┬─────┬─────┬─────┬─────┬─────┐
  row4-7   walk    │down │     │     │     │     │     │   ← 每个动作占 4 行
  row8-11  attack  ├─────┼─────┼─────┼─────┼─────┼─────┤
                   │ up  │     │     │     │     │     │
                   ├─────┼─────┼─────┼─────┼─────┼─────┤
                   │left │     │     │     │     │     │
                   ├─────┼─────┼─────┼─────┼─────┼─────┤
                   │right│     │     │     │     │     │
                   └─────┴─────┴─────┴─────┴─────┴─────┘
```

- 每帧尺寸由描述文件的 `frame_size` 指定（当前 64×64）。
- 动作行数、列数、帧率都可在描述文件里改，不写死在代码中。

## 描述文件（`hero.json`）

```json
{
  "name": "hero",
  "sheet": "res://assets/sprites/hero.png",
  "frame_size": { "w": 64, "h": 64 },
  "directions": ["down", "up", "left", "right"],
  "actions": {
    "idle":   { "row_start": 0, "columns": 6, "fps": 6,  "loop": true },
    "walk":   { "row_start": 4, "columns": 6, "fps": 10, "loop": true },
    "attack": { "row_start": 8, "columns": 6, "fps": 12, "loop": false }
  }
}
```

| 字段 | 说明 |
|------|------|
| `sheet` | 贴图路径（Godot `res://` 路径） |
| `frame_size` | 单帧宽高，切图用 |
| `directions` | 行的朝向顺序，**必须与 `row_start` 对应** |
| `actions.*.row_start` | 该动作第一行在 sheet 中的行号 |
| `actions.*.columns` | 该动作有几帧 |
| `actions.*.fps` | 播放帧率 |
| `actions.*.loop` | 是否循环（`attack` 等一次性动作用 `false`） |

生成的动画名 = `"<动作>_<朝向>"`，例如 `idle_down` / `walk_left` / `attack_up`。

### 两种布局都支持

| 布局 | `directions` | 说明 |
|------|-------------|------|
| **4 行**（当前） | `["down","up","left","right"]` | 每个方向独立绘制，不需要翻转。**推荐**：斜向和侧向都由美术控制，表现最好 |
| 3 行 | `["down","up","side"]` | `side` 画"朝右"，朝左由代码 `flip_h` 镜像。美术量少 1/4 |

`facing.gd` 的 `render_for()` 会自动适配：先找精确匹配的行，找不到再退回 `side` + 镜像。
**美术换布局时只改 JSON，代码不用动。**

## 朝向数据流

```
服务端                                    客户端
Move:onTick
  set("dir", math.atan(dy, dx))   ──▶   object add 的 props.dir (全量)
  (sync="all" 自动下发)                  prop props 的 d.dir (增量)
                                              │
                                              ▼
                                     Direction.quantize(dir)  连续角度 -> 4 向
                                              │
                                              ▼
                                     Facing.render_for(4向, directions)  -> 行 + 是否翻转
                                              │
                                              ▼
                                     ActorNode 播放 "<动作>_<朝向>"
```

- **自己**：按下方向键立即用输入预测朝向（转向无延迟），服务器 `prop` 回来后以服务端值为准。
- **他人**：直接用同步来的 `dir`。
- **施法时**：转向目标（本地表现）。

## 角度约定

`dir` 是**连续角度**（弧度），与 `math.cos/math.sin` 一致：

| 角度 | 方向 |
|------|------|
| `0` | 右 |
| `π/2` (≈1.5708) | 下 |
| `π` (≈3.1416) | 左 |
| `-π/2` | 上 |

世界坐标 x 向右为正、y 向下为正（与屏幕坐标一致）。

**量化分界**（90 度一个方向，实测自服务端）：

```
        [315,360)∪[0,45) -> RIGHT
        [45,135)         -> DOWN
        [135,225)        -> LEFT
        [225,315)        -> UP
```

注意 45° 本身归 **RIGHT**、46° 才归 DOWN——这与"取最近中心角"的 45° 对分模型**不同**，容易混淆。

## 实现说明：为什么是移植而非直接调用

服务端的 `tinyworld/core/direction.lua` 是**纯 Lua 模块且不经协议下发**（只是服务端内部工具），
Godot 客户端是 GDScript，无法 `require` Lua 模块，因此 `core/protocol/direction.gd` 按其语义等价值实现了一份。

> ⚠️ 服务端该模块若变更语义，`direction.gd` 需同步。
> 回归靠 `test/test_direction_parity.gd`（对拍服务端 1441 个采样点）。

**已知差异**：在多圈角度（如 495° = 135°+360°）上，服务端**自身不自洽**
（`quantize(135°)=DOWN` 但 `quantize(495°)=LEFT`，浮点噪声导致）。因此对拍仅要求
**单圈角度**（|deg| ≤ 180）逐点一致——而游戏里 `dir` 由 `math.atan` 产出，恒为单圈
`[-π, π)`，多圈不会出现。

## 新增角色/怪物

1. 按上面的布局出一张 sheet；
2. 复制一份 `hero.json` 改成新名字；
3. 在创建 `ActorNode` 时传入对应的描述文件路径。

> 当前 `ActorNode` 默认加载 `res://assets/sprites/hero.json`（见 `actor_node.gd` 的 `DEFAULT_DESC`）。
> 多角色时改为按 `kind` / 配置查表即可。
