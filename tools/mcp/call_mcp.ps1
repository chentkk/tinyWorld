# Godot AI MCP client (Windows side). Reads request from req.json, writes resp.txt
param([string]$Method, [string]$ParamsJson, [string]$SessionId = "")
$ErrorActionPreference = 'Stop'
$dir = 'C:\Users\chentongke\mcp_tmp'
$req = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = (ConvertFrom-Json $ParamsJson) } | ConvertTo-Json -Depth 20 -Compress
Set-Content -Path "$dir\req.json" -Value $req -Encoding utf8
$headers = @{ 'Accept' = 'application/json, text/event-stream'; 'Content-Type' = 'application/json' }
if ($SessionId -ne "") { $headers['Mcp-Session-Id'] = $SessionId }
try {
  $r = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8000/mcp' -Method POST -Headers $headers -Body (Get-Content -Raw "$dir\req.json") -TimeoutSec 120
  $sid = $r.Headers['Mcp-Session-Id']
  if ($sid) { Set-Content -Path "$dir\session.txt" -Value $sid -Encoding utf8 }
  Set-Content -Path "$dir\resp.txt" -Value $r.Content -Encoding utf8
} catch {
  "ERR=" + $_.Exception.Message | Set-Content -Path "$dir\resp.txt" -Encoding utf8
}
