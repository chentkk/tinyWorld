# tinyWorld 登录/游玩协议 Review

> 检查目的：当前协议能否让一个**独立客户端**完整进入游戏进行游玩（登录、数据创建、资源加载）。
> 结论：**框架运行时同步完整可用，但静态配置/资源加载协议完全缺失**，独立客户端目前无法"完整游玩"。

## 1. 已具备（可正常使用）

### 登录 / 角色
- HTTP `/login?name=&password=` → `{code, accountId, token}`
- `AUTH auth{token}` → `AUTH auth_ok / auth_fail`
- `ACCOUNT characterList / spaceInfo / createCharacter / selectCharacter`

### 进入世界
- `object add{entityId, kind, props, isSelf}`：自己全量属性快照
- `record current_tasks`：初始 record 全量（add op 逐行）
- `view bag / view equipment`：初始 view 全量（add op 逐子对象）
- `view modifiers_view / view abilities_view`：selfOnly 视图（稍后到达）

### 世界运行时同步
- `prop props{entityId, ...changedFields, seq?}`：属性增量
- `record <name>{entityId, ops}`：`add/remove/set`
- `view <name>{entityId, ops}`：`add/remove/set/view`
- `object add/remove`：视野进出
- `RPC` 业务方法 + 战斗事件推送

### 移动与战斗表现
- 移动：`RPC onRequestMove{seq,dt,dirX,dirY}`；服务器 prop 回 `seq` 用于 Reconciliation
- 战斗：`RPC onCombatDamage / onCombatHeal`

### 退出 / 重登录
- 断开自动 despawn real、清理 ghost、保存 player_bin
- 同账号重登录旧连接被顶替
- gate message.log 每连接 connect/disconnect 严格配对

## 2. 缺失（完整游玩阻塞点）

### 2.1 静态配置 / 资源协议缺失

服务器从不向客户端下发静态定义，只下发运行时状态。

| 客户端需要 | 当前情况 |
|-----------|---------|
| 物品显示（名称/图标/属性） | 只有 `itemId` 数字 |
| 技能 UI（cooldown/施法距离/damage/描述/图标） | 只有 `id/state/cooldownLeft/level`；数值在服务端 npc txt 未下发 |
| modifier 显示（名称/图标/效果） | 只有 `id/name/stack/duration/remaining` |
| 任务显示（标题/描述/目标/奖励） | 只有 `taskid/state/progress` |
| 角色外观/职业/初始属性 | `createCharacter` 只能传 name；模板服务端硬编码 |
| 实体模型/动画/特效资源映射 | `kind` 只有字符串，无渲染定义 |
| 场景/UI 资源清单、资源版本号 | 无 |

### 2.2 结构性缺口

1. demo 客户端依赖 `package.path = "../server/?.lua"` 直接 require 服务端代码，
   独立客户端无法复用。
2. 没有统一的 `CONFIG / RESOURCE / SYSTEM` 协议大类。
3. 没有配置版本号 / 增量下发 / 热更。
4. 初始 world 快照与增量同步没有显式标志（客户端靠"首次 add op"推断）。
5. 没有服务器时间同步包。
6. `createCharacter` 参数过少，无法选外观/职业/初始属性。

## 3. 建议扩展方向

### 3.1 静态配置下发

```json
// 客户端按需拉取
{ "t": "CONFIG", "n": "load", "d": { "group": "item", "version": 0 } }

// 服务器响应
{
  "t": "CONFIG", "n": "loaded",
  "d": {
    "group": "item",
    "version": 1,
    "entries": [
      { "itemId": 7001, "name": "短剑", "icon": "icon_sword",
        "attrs": { "atk": 5 } }
    ]
  }
}
```

- group 至少包括：`item`、`ability`、`modifier`、`task`、`entity`、`resource`。

### 3.2 资源清单 / 版本

```json
{ "t": "RESOURCE", "n": "loadList", "d": { "bundle": "icons", "version": 0 } }
```

### 3.3 时间同步

```json
{ "t": "SYSTEM", "n": "serverTime", "d": { "t": 1730000000, "frame": 1234 } }
```

### 3.4 扩展角色创建

```json
{ "t": "ACCOUNT", "n": "createCharacter", "d": {
    "name": "hero",
    "appearance": { "model": "human_m", "hair": 1 },
    "class": "warrior"
} }
```

### 3.5 显式 snapshot 标志

```json
{ "t": "record", "n": "current_tasks", "d": { "entityId": 1, "snapshot": true, "ops": [...] } }
{ "t": "view", "n": "bag", "d": { "entityId": 1, "snapshot": true, "ops": [...] } }
```

## 4. 结论

- **登录/退出/运行时状态同步：可用且稳定**。
- **静态配置/资源加载：完全缺失**。
- 要支持独立客户端"完整游玩"，下一步应先设计并实现 `CONFIG/RESOURCE` 两套协议和服务端配置导出层。
