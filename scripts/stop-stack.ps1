# Stop Nebula umbrella stack: console, cti-core, hunt, intel, optional peers.
# Default: recorded PIDs + loopback port owners for product ports + MISP/postgres compose down.
# Hermes (:8791) only if recorded in pids.json or -ForceHermes.
# Idempotent / safe when already stopped. Never prints secrets. Never touches remote hosts.
param(
  [switch]$ForcePorts,   # legacy alias — port kill is now default; kept for callers
  [switch]$ForceHunt,    # legacy alias — hunt/intel ports included by default
  [switch]$ForceHermes,  # also stop whatever owns :8791 even if not in pids.json
  [switch]$PidsOnly,     # only kill PIDs from logs/pids.json (no port / docker)
  [switch]$LeaveDocker   # skip MISP + postgres compose down
)
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$PidFile = Join-Path $Root "logs\pids.json"
$EnvFile = Join-Path $Root ".env"

# Load CTI_ROOT (and friends) without printing values.
if (Test-Path $EnvFile) {
  Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    if ($_ -match '^\s*([A-Za-z0-9_]+)=(.*)$') {
      $name = $matches[1]
      $val = $matches[2].Trim().Trim('"').Trim("'")
      if (-not [Environment]::GetEnvironmentVariable($name, "Process")) {
        [Environment]::SetEnvironmentVariable($name, $val, "Process")
      }
    }
  }
}

$CtiRoot = if ($env:CTI_ROOT) { $env:CTI_ROOT } else { "C:\Users\MOHD\Desktop\Projects\CTI" }

$hadHermesPid = $false
if (Test-Path $PidFile) {
  try {
    $pids = Get-Content $PidFile -Raw | ConvertFrom-Json
  } catch {
    $pids = $null
  }
  if ($pids) {
    foreach ($name in @("console", "cti", "hunt", "intel", "hermes")) {
      $id = $pids.$name
      if ($id) {
        if ($name -eq "hermes") { $hadHermesPid = $true }
        Write-Host "Stopping $name pid=$id"
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
      }
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
    Write-Host "Stopping pid=$id on :$Port"
    Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
  }
}

# Default: stop product listeners (ForcePorts/ForceHunt kept as no-ops / aliases).
if (-not $PidsOnly) {
  foreach ($port in @(5173, 8790, 8788, 8787)) {
    Stop-PortOwner $port
  }
  # Hermes only when stack recorded it, or operator asked.
  # Legacy -ForcePorts / -ForceHunt remain accepted (ports already stopped above).
  $null = $ForcePorts
  $null = $ForceHunt
  if ($hadHermesPid -or $ForceHermes) {
    Stop-PortOwner 8791
  }
}

function Stop-ComposeProfile {
  param(
    [string]$ComposeFile,
    [string]$Profile,
    [string]$Label,
    [string]$EnvFilePath
  )
  if (-not (Test-Path $ComposeFile)) {
    Write-Host ('[skip] {0} - compose missing: {1}' -f $Label, $ComposeFile)
    return
  }
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host ('[skip] {0} - docker not found' -f $Label)
    return
  }
  try {
    docker info 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) { throw "docker info failed" }
  } catch {
    Write-Host ('[skip] {0} - Docker engine not reachable' -f $Label)
    return
  }

  # Placeholders satisfy ${VAR:?} interpolation on `down` when env file is incomplete.
  # Values are never printed.
  if (-not $env:MISP_DB_PASSWORD) { $env:MISP_DB_PASSWORD = "unused-for-down" }
  if (-not $env:MISP_DB_ROOT_PASSWORD) { $env:MISP_DB_ROOT_PASSWORD = "unused-for-down" }
  if (-not $env:MISP_ADMIN_KEY) { $env:MISP_ADMIN_KEY = ("x" * 40) }
  if (-not $env:CTI_API_TOKEN) { $env:CTI_API_TOKEN = "unused-for-down" }
  if (-not $env:POSTGRES_PASSWORD) { $env:POSTGRES_PASSWORD = "unused-for-down" }

  Write-Host ('[..] {0} - docker compose --profile {1} down' -f $Label, $Profile)
  $dcArgs = @("compose", "-f", $ComposeFile)
  if ($EnvFilePath -and (Test-Path $EnvFilePath)) {
    $dcArgs += @("--env-file", $EnvFilePath)
  }
  $dcArgs += @("--profile", $Profile, "down")
  & docker @dcArgs 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Host ('[ok] {0} down (or already stopped)' -f $Label)
  } else {
    Write-Host ('[warn] {0} compose down exited {1} (ignored; idempotent best-effort)' -f $Label, $LASTEXITCODE)
  }
}

if (-not $PidsOnly -and -not $LeaveDocker) {
  $mispCompose = Join-Path $CtiRoot "fixtures\docker-compose.misp.yml"
  $mispEnv = Join-Path $CtiRoot ".env.misp.local"
  Stop-ComposeProfile -ComposeFile $mispCompose -Profile "misp" -Label "MISP peer (:8443)" -EnvFilePath $mispEnv

  $pgCompose = Join-Path $CtiRoot "deploy\docker-compose.prod.yml"
  $ctiEnv = Join-Path $CtiRoot ".env"
  Stop-ComposeProfile -ComposeFile $pgCompose -Profile "postgres" -Label "Postgres profile" -EnvFilePath $ctiEnv
}

Write-Host "Done."
& (Join-Path $PSScriptRoot "status.ps1")
