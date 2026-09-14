# Godot MCP 调用工具 (WSL 侧)

Godot AI MCP 服务由 Godot 编辑器在 **Windows** 侧启动，监听 `127.0.0.1:8000`
(streamable-http)。WSL 的 `127.0.0.1` 访问不到 Windows loopback，因此本工具通过
`powershell.exe` 走 Windows 本地回环调用 MCP。

## 组成
- `call_mcp.ps1` — Windows 侧执行体：把一个 JSON-RPC 请求 POST 到 `http://127.0.0.1:8000/mcp`，
  结果写入 `C:\Users\<user>\mcp_tmp\resp.txt`，会话 id 写入 `session.txt`。
- `godot_mcp.py` — WSL 侧客户端：构造请求 → 调用 `call_mcp.ps1` → 解析 SSE 响应。

## 用法
```bash
tools/mcp/godot_mcp.py init                 # 建立会话(保存 session id)
tools/mcp/godot_mcp.py list                 # 列出可用工具
tools/mcp/godot_mcp.py call editor_state '{}'
tools/mcp/godot_mcp.py call scene_get_hierarchy '{}'
```

## 注意
- 需要 Windows 侧 Godot 编辑器已启动, 且 godot-ai MCP 服务在运行。
- 路径/用户名与 Windows 账户相关, 如不同请改 `godot_mcp.py` 中的 `WSL_DIR` / `WIN_DIR`。
