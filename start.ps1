# One-command product run (Windows). Prefer reusing live listeners on loopback ports.
$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "scripts\start-stack.ps1")
