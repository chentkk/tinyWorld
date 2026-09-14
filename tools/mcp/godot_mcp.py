#!/usr/bin/env python3
"""通过 Windows loopback 调用 Godot AI MCP (streamable-http @ 127.0.0.1:8000)。

Godot MCP 只监听 Windows 的 127.0.0.1, WSL 直连不到, 因此:
  WSL 写 req.json -> 调 powershell call_mcp.ps1 (走 Windows loopback) -> 读 resp.txt

用法:
  godot_mcp.py init                 # 建立会话, 保存 session id
  godot_mcp.py list                 # tools/list
  godot_mcp.py call <tool> '<json>' # tools/call, json 为 arguments
  godot_mcp.py raw <method> '<json>'# 任意方法
"""
import json, os, subprocess, sys

PS = "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
WIN_DIR = r"C:\Users\chentongke\mcp_tmp"
WSL_DIR = "/mnt/c/Users/chentongke/mcp_tmp"
os.makedirs(WSL_DIR, exist_ok=True)
SID_FILE = os.path.join(WSL_DIR, "sid.txt")

def _read(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8-sig", errors="replace")

def _session():
    if os.path.exists(SID_FILE):
        return _read(SID_FILE).strip()
    return ""

def rpc(method, params, session=None):
    """发一次 JSON-RPC, 返回解析后的 result (或抛错)。"""
    req = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}}
    with open(os.path.join(WSL_DIR, "req.json"), "w", encoding="utf-8") as f:
        json.dump(req, f)
    args = [PS, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            WIN_DIR + r"\call_mcp.ps1", "-Method", method,
            "-ParamsJson", json.dumps(params or {})]
    if session:
        args += ["-SessionId", session]
    subprocess.run(args, capture_output=True)
    raw = _read(os.path.join(WSL_DIR, "resp.txt"))
    if raw.startswith("ERR="):
        raise RuntimeError(raw.strip())
    # 解析 SSE
    for line in raw.splitlines():
        line = line.strip()
        if line.startswith("data:"):
            obj = json.loads(line[5:].strip())
            if "error" in obj:
                raise RuntimeError(json.dumps(obj["error"], ensure_ascii=False))
            return obj.get("result")
    # 纯 JSON 兜底
    obj = json.loads(raw)
    if "error" in obj:
        raise RuntimeError(json.dumps(obj["error"], ensure_ascii=False))
    return obj.get("result")

def init():
    # initialize 后, session id 由 ps1 写入 session.txt
    rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                       "clientInfo": {"name": "wsl-cli", "version": "0.1"}})
    sid = _read(os.path.join(WSL_DIR, "session.txt")).strip()
    with open(SID_FILE, "w", encoding="utf-8") as f:
        f.write(sid)
    return sid

def ensure():
    sid = _session()
    if not sid:
        sid = init()
    return sid

def main():
    if len(sys.argv) < 2:
        print(__doc__); return
    cmd = sys.argv[1]
    if cmd == "init":
        print("session:", init()); return
    sid = ensure()
    if cmd == "list":
        res = rpc("tools/list", {}, sid)
        tools = res.get("tools", [])
        print("tools:", len(tools))
        for t in tools:
            print("  -", t["name"], "-", (t.get("description") or "").split("\n")[0][:80])
    elif cmd == "call":
        tool = sys.argv[2]
        args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        res = rpc("tools/call", {"name": tool, "arguments": args}, sid)
        print(json.dumps(res, ensure_ascii=False, indent=2))
    elif cmd == "raw":
        method = sys.argv[2]
        params = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        print(json.dumps(rpc(method, params, sid), ensure_ascii=False, indent=2))
    else:
        print(__doc__)

if __name__ == "__main__":
    main()
