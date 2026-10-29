# Best-effort stop of umbrella-started PIDs (does not kill foreign/live listeners by default).
# Pass -ForcePorts to also stop whatever owns :5173/:8790 (never force-kills hunt/intel unless -ForceHunt).
param(
  [switch]$ForcePorts,
  [switch]$ForceHunt
)
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$PidFile = Join-Path $Root "logs\pids.json"

if (Test-Path $PidFile) {
  $pids = Get-Content $PidFile -Raw | ConvertFrom-Json
  foreach ($name in @("console", "cti", "hunt", "intel")) {
    $id = $pids.$name
    if ($id) {
      Write-Host "Stopping $name pid=$id"
      Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
  }
  Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
} else {
  Write-Host "No pids.json - nothing recorded by this umbrella."
}

function Stop-PortOwner([int]$Port) {
  $owns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique
  foreach ($id in $owns) {
    Write-Host "Force-stopping pid=$id on :$Port"
    Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
  }
}

if ($ForcePorts) {
  Stop-PortOwner 5173
  Stop-PortOwner 8790
}
if ($ForceHunt) {
  Stop-PortOwner 8788
  Stop-PortOwner 8787
}

Write-Host "Done."
& (Join-Path $PSScriptRoot "status.ps1")
