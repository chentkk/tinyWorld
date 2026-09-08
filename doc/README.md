# tinyWorld 文档

给客户端/服务端开发者阅读的文档集合。

## 文档列表

| 文档 | 说明 |
|------|------|
| [protocol.md](./protocol.md) | 通信协议：帧格式、JSON 信封、消息类型、字段、RPC 方法 |
| [login_flow.md](./login_flow.md) | 登录 / 退出 / 重复登录流程、状态机、时序 |
| [client_dev_guide.md](./client_dev_guide.md) | 客户端开发指南：最小帧收发、登录骨架、实体/record/view 维护、移动参考 |
| [protocol_review.md](./protocol_review.md) | 协议 Review：现有能力、缺失的静态配置/资源加载、扩展方向 |

## 快速开始顺序（新客户端）

1. 读 `protocol.md`（协议）。
2. 读 `login_flow.md`（端到端时序）。
3. 读 `client_dev_guide.md`（代码骨架与状态机）。

## 服务端关键文件索引

| 职责 | 路径 |
|------|------|
| 协议信封 / 具体消息构造 | `server/tinyworld/net/protocol.lua` |
| JSON 编解码 / 帧打包 | `server/tinyworld/core/proto.lua` |
| 登录 HTTP | `server/tinyworld/app/login/login.lua` |
| 网关（帧/认证/转发） | `server/tinyworld/app/gate/gate.lua` |
| base 会话/角色/存盘 | `server/tinyworld/app/baseapp/baseapp.lua` |
| base 实体 | `server/tinyworld/app/baseapp/baseentity.lua` |
| 角色存储(DB/bin) | `server/tinyworld/app/baseapp/player_store.lua` |
| cell 侧 real 生命周期 | `server/tinyworld/app/cellapp/cellapp.lua` |
| 实体基类 / 生命周期 | `server/tinyworld/entity/entity.lua` |
| 属性同步 | `server/tinyworld/schema/property.lua` |
| 表格同步 | `server/tinyworld/schema/record.lua` |
| 视图/容器同步 | `server/tinyworld/schema/container.lua` |

## 客户端目录

- 现有客户端参考：`client/`（LÖVE + LuaJIT）。
- 登录/收发帧参考实现：`client/src/net.lua`。
