# Start hunt (:8788) + cti-core (:8790) + cti-console (:5173) from leaf paths.
# Loads .env next to this repo (never prints secret values).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root ".env"
if (-not (Test-Path $EnvFile)) {
  Write-Error "Missing $EnvFile — copy .env.example to .env and set paths/tokens."
}

Get-Content $EnvFile | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
  if ($_ -match '^\s*([A-Za-z0-9_]+)=(.*)$') {
    $name = $matches[1]
    $val = $matches[2].Trim().Trim('"').Trim("'")
    [Environment]::SetEnvironmentVariable($name, $val, "Process")
  }
}

$CtiRoot = if ($env:CTI_ROOT) { $env:CTI_ROOT } else { "C:\Users\MOHD\Desktop\Projects\CTI" }
$HuntRoot = if ($env:HUNT_ROOT) { $env:HUNT_ROOT } else { "C:\Users\MOHD\hunt-platform" }

if (-not (Test-Path $CtiRoot)) { Write-Error "CTI_ROOT not found: $CtiRoot" }
if (-not (Test-Path $HuntRoot)) { Write-Error "HUNT_ROOT not found: $HuntRoot" }

if (-not $env:VITE_HUNT_TOKEN -and $env:NEBULA_HUMAN_TOKEN) {
  $env:VITE_HUNT_TOKEN = $env:NEBULA_HUMAN_TOKEN
}
if (-not $env:VITE_HUNT_API_URL) { $env:VITE_HUNT_API_URL = "http://127.0.0.1:8788" }
if (-not $env:VITE_HUNT_PLATFORM_URL) { $env:VITE_HUNT_PLATFORM_URL = "http://127.0.0.1:8788" }
if (-not $env:HUNT_PLATFORM_URL) { $env:HUNT_PLATFORM_URL = "http://127.0.0.1:8788" }
if (-not $env:HUNT_PLATFORM_TOKEN -and $env:NEBULA_HUMAN_TOKEN) {
  $env:HUNT_PLATFORM_TOKEN = $env:NEBULA_HUMAN_TOKEN
}

$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$PidFile = Join-Path $LogDir "pids.json"
$pids = @{}

function Test-Port([int]$Port) {
  return [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

# Hunt (prefer existing listener; else try WSL/dev.sh or local uvicorn)
if (Test-Port 8788) {
  Write-Host "[ok] hunt already on :8788"
} else {
  $devSh = Join-Path $HuntRoot "scripts\dev.sh"
  if (Test-Path $devSh) {
    Write-Host "[..] starting hunt via WSL scripts/dev.sh"
    $huntProc = Start-Process -FilePath "wsl.exe" -ArgumentList "-e","bash","-lc","cd /mnt/c/Users/MOHD/hunt-platform && HUNT_NO_SECRETS=1 ./scripts/dev.sh" -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $LogDir "hunt.out.log") -RedirectStandardError (Join-Path $LogDir "hunt.err.log")
    $pids.hunt = $huntProc.Id
  } else {
    Write-Warning "Hunt not listening on :8788 and scripts/dev.sh missing — start hunt-platform manually."
  }
}

# cti-core
if (Test-Port 8790) {
  Write-Host "[ok] cti-core already on :8790"
} else {
  $coreDir = Join-Path $CtiRoot "services\cti-core"
  $env:PYTHONPATH = Join-Path $coreDir "src"
  $env:CTI_HOST = "127.0.0.1"
  $env:CTI_PORT = "8790"
  Write-Host "[..] starting cti-core :8790"
  $coreProc = Start-Process -FilePath "python" -ArgumentList "-m","uvicorn","cti_core.main:app","--host","127.0.0.1","--port","8790" -WorkingDirectory $coreDir -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $LogDir "cti.out.log") -RedirectStandardError (Join-Path $LogDir "cti.err.log")
  $pids.cti = $coreProc.Id
}

# console — write ephemeral .env.local under leaf (gitignored *.local)
$consoleDir = Join-Path $CtiRoot "apps\cti-console"
$envLocal = Join-Path $consoleDir ".env.local"
@(
  "VITE_HUNT_API_URL=$($env:VITE_HUNT_API_URL)",
  "VITE_HUNT_PLATFORM_URL=$($env:VITE_HUNT_PLATFORM_URL)",
  "VITE_HUNT_TOKEN=$($env:VITE_HUNT_TOKEN)"
) | Set-Content -Path $envLocal -Encoding UTF8

if (Test-Port 5173) {
  Write-Host "[ok] console already on :5173 (restart manually if token changed)"
} else {
  Write-Host "[..] starting cti-console :5173"
  $consoleProc = Start-Process -FilePath "npm.cmd" -ArgumentList "run","dev","--","--host","127.0.0.1","--port","5173","--strictPort" -WorkingDirectory $consoleDir -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $LogDir "console.out.log") -RedirectStandardError (Join-Path $LogDir "console.err.log")
  $pids.console = $consoleProc.Id
}

$pids | ConvertTo-Json | Set-Content $PidFile -Encoding UTF8
Start-Sleep -Seconds 3
Write-Host ""
Write-Host "Stack targets:"
Write-Host "  CTI     http://127.0.0.1:8790/health"
Write-Host "  Hunt    http://127.0.0.1:8788/v1/health"
Write-Host "  Console http://127.0.0.1:5173  (Hunt → Cases)"
Write-Host "Logs: $LogDir"
