# tinyWorld 客户端

本目录下的客户端**都对接同一份服务器协议**（见 [`doc/protocol.md`](../doc/protocol.md)）。

| 客户端 | 位置 | 状态 | 说明 |
|--------|------|------|------|
| **Godot 客户端** | [`godot/`](./godot/) | **主力，持续维护** | Godot 4.x + GDScript，2D MMORPG 客户端 |
| LÖVE Lua 客户端 | [`../tools/love_client/`](../tools/love_client/) | 已冻结，仅参考 | Lua + LÖVE，最早的协议跑通实现，可作协议对照 |

## 目录

```
client/
├── godot/            # 主力客户端 (Godot 4.x)
│   ├── core/         #   框架层: 协议 / 帧编解码 / TCP / HTTP
│   ├── game/         #   玩法层: 登录状态机 / 世界状态 / 移动预测
│   ├── ui/           #   表现层: HUD / 面板 / 实体 / 网格 / 特效
│   ├── scenes/       #   场景 (.tscn)
│   ├── scripts/      #   入口装配 (main.gd)
│   └── README.md     #   详见此文档
└── README.md         # 本文件
```

## 快速开始

1. 启动服务器（见仓库根 `README.md`）。
2. 用 Godot 4.x 打开 `client/godot/`，运行主场景。

默认账号 `test1` / 密码 `123456`，可在命令行覆盖：

```bash
godot --path client/godot -- --account=test2
```

详见 [`godot/README.md`](./godot/README.md)。
