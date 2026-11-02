# Start (or reuse) intel-core :8787 + hunt-api :8788 + cti-core :8790 + cti-console :5173.
# Loads umbrella .env into this process only. Never prints secret values.
# Does not write into leaf working trees (sibling agents may own those checkouts).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root ".env"
if (-not (Test-Path $EnvFile)) {
  Write-Error "Missing $EnvFile - copy .env.example to .env and set paths/tokens."
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
$SkipStart = ($env:NEBULA_REUSE_ONLY -eq "1")

if (-not (Test-Path $CtiRoot)) { Write-Error "CTI_ROOT not found: $CtiRoot" }
if (-not (Test-Path $HuntRoot)) { Write-Error "HUNT_ROOT not found: $HuntRoot" }

if (-not $env:VITE_HUNT_TOKEN -and $env:NEBULA_HUMAN_TOKEN) {
  $env:VITE_HUNT_TOKEN = $env:NEBULA_HUMAN_TOKEN
}
if (-not $env:VITE_HUNT_API_URL) { $env:VITE_HUNT_API_URL = "http://127.0.0.1:8788" }
if (-not $env:VITE_HUNT_PLATFORM_URL) { $env:VITE_HUNT_PLATFORM_URL = "http://127.0.0.1:8788" }
if (-not $env:HUNT_PLATFORM_URL) { $env:HUNT_PLATFORM_URL = "http://127.0.0.1:8788" }
if (-not $env:INTEL_CORE_URL) { $env:INTEL_CORE_URL = "http://127.0.0.1:8787" }
if (-not $env:HUNT_PLATFORM_TOKEN -and $env:NEBULA_HUMAN_TOKEN) {
  $env:HUNT_PLATFORM_TOKEN = $env:NEBULA_HUMAN_TOKEN
}

$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$PidFile = Join-Path $LogDir "pids.json"
$pids = @{}
if (Test-Path $PidFile) {
  try {
    $prev = Get-Content $PidFile -Raw | ConvertFrom-Json
    foreach ($k in @("intel", "hunt", "cti", "console")) {
      if ($prev.$k) { $pids[$k] = [int]$prev.$k }
    }
  } catch {
    $pids = @{}
  }
}

function Test-Port([int]$Port) {
  return [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

function Wait-Port([int]$Port, [int]$Seconds = 25) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Port $Port) { return $true }
    Start-Sleep -Milliseconds 400
  }
  return (Test-Port $Port)
}

# Hunt stack: intel-core (:8787) + hunt-api/platform (:8788) via hunt-platform scripts/dev.sh
$needHunt = -not ((Test-Port 8787) -and (Test-Port 8788))
if (-not $needHunt) {
  Write-Host "[ok] intel-core already on :8787"
  Write-Host "[ok] hunt-api already on :8788"
} elseif ($SkipStart) {
  Write-Warning "NEBULA_REUSE_ONLY=1 and hunt ports down - not starting leaves."
} else {
  $devSh = Join-Path $HuntRoot "scripts\dev.sh"
  if (Test-Path $devSh) {
    Write-Host "[..] starting hunt stack (intel :8787 + hunt-api :8788) via WSL scripts/dev.sh"
    # HUNT_NO_SECRETS=1 avoids loading host secrets file into agent logs; operator can unset in .env
    $noSecrets = if ($env:HUNT_NO_SECRETS) { $env:HUNT_NO_SECRETS } else { "1" }
    $huntProc = Start-Process -FilePath "wsl.exe" `
      -ArgumentList "-e","bash","-lc","cd /mnt/c/Users/MOHD/hunt-platform && HUNT_NO_SECRETS=$noSecrets ./scripts/dev.sh" `
      -PassThru -WindowStyle Hidden `
      -RedirectStandardOutput (Join-Path $LogDir "hunt.out.log") `
      -RedirectStandardError (Join-Path $LogDir "hunt.err.log")
    $pids["hunt"] = $huntProc.Id
    $pids["intel"] = $huntProc.Id
    [void](Wait-Port 8787 40)
    [void](Wait-Port 8788 40)
  } else {
    Write-Warning "Hunt not listening and scripts/dev.sh missing - start hunt-platform manually."
  }
}

# cti-core
if (Test-Port 8790) {
  Write-Host "[ok] cti-core already on :8790"
} elseif ($SkipStart) {
  Write-Warning "NEBULA_REUSE_ONLY=1 and :8790 down - not starting cti-core."
} else {
  $coreDir = Join-Path $CtiRoot "services\cti-core"
  $env:PYTHONPATH = Join-Path $coreDir "src"
  $env:CTI_HOST = "127.0.0.1"
  $env:CTI_PORT = "8790"
  Write-Host "[..] starting cti-core :8790"
  $coreProc = Start-Process -FilePath "python" `
    -ArgumentList "-m","uvicorn","cti_core.main:app","--host","127.0.0.1","--port","8790" `
    -WorkingDirectory $coreDir -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $LogDir "cti.out.log") `
    -RedirectStandardError (Join-Path $LogDir "cti.err.log")
  $pids["cti"] = $coreProc.Id
  [void](Wait-Port 8790 30)
}

# console - pass Vite env via process inheritance; do not write leaf .env.local
if (Test-Port 5173) {
  Write-Host "[ok] console already on :5173 (restart manually if token env changed)"
} elseif ($SkipStart) {
  Write-Warning "NEBULA_REUSE_ONLY=1 and :5173 down - not starting console."
} else {
  $consoleDir = Join-Path $CtiRoot "apps\cti-console"
  Write-Host "[..] starting cti-console :5173 (env from umbrella .env, no leaf writes)"
  $consoleProc = Start-Process -FilePath "npm.cmd" `
    -ArgumentList "run","dev","--","--host","127.0.0.1","--port","5173","--strictPort" `
    -WorkingDirectory $consoleDir -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $LogDir "console.out.log") `
    -RedirectStandardError (Join-Path $LogDir "console.err.log")
  $pids["console"] = $consoleProc.Id
  [void](Wait-Port 5173 45)
}

$pids | ConvertTo-Json | Set-Content $PidFile -Encoding UTF8

Write-Host ""
Write-Host "Access URLs (loopback):"
Write-Host "  Console   http://127.0.0.1:5173"
Write-Host "  cti-core  http://127.0.0.1:8790/health"
Write-Host "  hunt-api  http://127.0.0.1:8788/v1/health"
Write-Host "  intel     http://127.0.0.1:8787/v1/health"
Write-Host "Logs: $LogDir"
Write-Host "Health: .\scripts\status.ps1"
& (Join-Path $PSScriptRoot "status.ps1")
