# tinyWorld

基于 skynet 的 MMORPG 通用服务器框架(reference: bigworld)。所有 skynet 服务运行在同一个
节点, 服务命名、概念(cell_info / server_space 等)对齐 bigworld, 文件名小写, 函数名 camelCase,
服务命令小写下划线。

## 目录结构

```
server/
├── skynet/                 # skynet 引擎(运行时与 lualib)
├── tinyworld/              # 可复用框架(最通用内容)
│   ├── core/               # class / log / json / proto / bin / service / event / mockdb
│   ├── schema/             # property / record / container(View)
│   ├── entity/             # entity / component / baseentity / rpc 注册表 / defs 注册
│   ├── space/              # 共享空间底座: cell_info / space(网格划分)
│   ├── net/                # 协议信封与 message.log 格式化
│   └── app/                # 每类服务独立目录(各服务入口 + 仅本服务使用的代码)
│       ├── world/          # world 服务 + server_space + load_balancer
│       ├── cellapp/        # cellapp 服务 + local_space + cell + aoi + real/ghost 实体
│       ├── baseapp/        # baseapp 服务 + baseentity
│       ├── gate/           # gate 服务(连接管理 / AUTH / 收发包记录)
│       ├── login/          # login 服务(http 校验 + token)
│       ├── dbmgr/          # dbmgr 服务(多 db 负载均衡)
│       ├── db/             # db 服务(mysql / mock)
│       └── logservice/     # logservice 服务(message.log 写入)
└── game/                   # 项目相关代码
    ├── def/                # *_def 对象定义(属性 / 表格 / 容器, 支持 include)
    ├── components/         # move / bag / equipment / task / weather
    ├── scripts/            # 战斗技能系统(npc 数据 + vscripts 逻辑)
    ├── config/             # skynet config / spaces / schema(mock 初始化)
    ├── main.lua            # 启动编排
    └── logs/               # message.log 协议调试日志

client/                     # love2d 客户端
server/sql/init.sql         # mysql 建表脚本
server/test/                # 单元测试 + 性能压测
```

## 启动

```bash
cd server
./skynet/skynet game/config/config
```

默认 db_mode=mock(无 mysql 也能完整跑通登录流程), 接入 mysql 时改为
`db_mode = "mysql"` 并执行 `server/sql/init.sql`。

## 登录流程

1. 客户端 `GET http://127.0.0.1:8080/login?name=test1&password=123456` 拿到 token。
2. 连接 gate 8000, 发送 `AUTH auth{token=...}`。
3. `ACCOUNT characterList{}` 拉取角色, `ACCOUNT createCharacter{name=...}` 创建角色。
4. `ACCOUNT selectCharacter{playerId=1}` 进入世界: baseapp 加载 db 数据创建 baseentity,
   通过 world 选择 cell, 在 cellapp 创建 real entity(cell entity 唯一 id 由 cellappid 生成),
   之后向客户端下发 object add / record / view。
5. 进入世界后, 客户端与服务器交互均走 `RPC 方法名{参数}`(移动、背包、装备、任务等),
   不再新增私有消息 id。

## 单元测试 / 压测

```bash
cd server
lua test/run_all.lua        # 全部单元测试
lua test/perf_schema.lua    # schema 性能
lua test/perf_aoi.lua       # AOI 性能
```

## 同步客户端方式总结

- 对象属性: `prop props{entityId, ...}`
- 表格:     `record 表名{entityId, ops={add/remove/set}}`
- 视图/容器:`view 视图名{entityId, ops={add/remove/set/view}}`,
  视图自身有属性, 子对象同时包含属性与表格, 全量随 add op 下发。
- 对象增减: `object add{entityId, kind, props}` / `object remove{entityId}`

## message.log

所有收发协议由 gate 写入 `game/logs/message.log`, 连接号格式 `[gateId-序号]`,
在该文件出现的消息即为真实收发内容, 便于联调:
`[2026-08-26 15:01:00][1-1] recv AUTH auth{...}`。
