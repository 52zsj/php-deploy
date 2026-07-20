$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$env:SYNC_UI_HOST = if ($env:SYNC_UI_HOST) { $env:SYNC_UI_HOST } else { "127.0.0.1" }
$env:SYNC_UI_PORT = if ($env:SYNC_UI_PORT) { $env:SYNC_UI_PORT } else { "8765" }

$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $py) {
  Write-Error "Need Python 3 on PATH."
  exit 1
}
& $py.Source "script\sync-ui\app.py"
