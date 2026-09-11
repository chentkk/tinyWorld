# LÖVE Lua 客户端（协议参考实现）

> **状态：已冻结 / 仅作参考。** 主力客户端见 [`client/godot/`](../../client/godot/)。
> 本目录不再随协议演进而更新，保留它是因为：
> 1. 它是最早跑通 tinyWorld 协议的完整实现，可作为**协议对照**；
> 2. 排查服务端问题时可用它交叉验证（两套独立实现收到同样的帧，便于定位是客户端还是服务端的问题）。

## 目录

```
tools/love_client/
├── main.lua          # 入口：登录状态机 + 移动 + 绘制
└── src/
    ├── net.lua       # 帧收发（2 字节小端长度 + JSON）、登录接口
    ├── json.lua      # Lua 5.1 兼容 JSON 编解码
    ├── entities.lua  # 实体集合（object add/remove、prop）
    ├── records.lua   # record 表格增量（add/remove/set）
    ├── views.lua     # view 容器增量（add/remove/set/view）
    ├── move.lua      # 移动预测与 Reconciliation
    ├── ui.lua        # 背包 / 装备面板
    └── debuglog.lua  # 调试日志
```

## 运行

需要 [LÖVE](https://love2d.org/)（LuaJIT / Lua 5.1），且服务器已启动（登录 8080 / 游戏 8000）。

```bash
cd tools/love_client
love . test1 0        # 账号 test1，0 = 不自动退出
```

命令行参数：`love . <账号> [自动退出秒数] [automove] [cast] [技能index]`

## 与 Godot 客户端的关系

| | `tools/love_client/`（本目录） | `client/godot/` |
|---|---|---|
| 状态 | 冻结，仅参考 | 主力，持续维护 |
| 语言/引擎 | Lua + LÖVE (LuaJIT 5.1) | GDScript + Godot 4.x |
| 协议 | 同 `doc/protocol.md` | 同 `doc/protocol.md` |
| 复用服务端代码 | 是（`package.path` 上溯到 `server/`，共用 combat/scripts） | 否（完全独立实现） |

> 注意：本客户端通过 `package.path` 直接 `require` 服务端 Lua 代码（见 `main.lua` 顶部），
> 这是它必须留在仓库内、且依赖相对路径的原因（目录上溯两级到 `server/`）。
