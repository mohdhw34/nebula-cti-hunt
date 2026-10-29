# Best-effort stop of umbrella-started PIDs (does not kill foreign hunt/WSL by default).
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$PidFile = Join-Path $Root "logs\pids.json"
if (-not (Test-Path $PidFile)) {
  Write-Host "No pids.json — nothing recorded. Stop listeners manually if needed."
  exit 0
}
$pids = Get-Content $PidFile | ConvertFrom-Json
foreach ($name in @("console", "cti", "hunt")) {
  $id = $pids.$name
  if ($id) {
    Write-Host "Stopping $name pid=$id"
    Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
  }
}
Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
Write-Host "Done."
