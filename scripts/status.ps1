# Print which stack ports are listening (no secrets).
$ports = @(8790, 8788, 5173)
foreach ($p in $ports) {
  $listen = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($listen) {
    Write-Host ":$p LISTEN pid=$($listen.OwningProcess)"
  } else {
    Write-Host ":$p down"
  }
}
try { Write-Host "cti health: $((Invoke-WebRequest http://127.0.0.1:8790/health -UseBasicParsing).Content)" } catch { Write-Host "cti health: fail" }
try { Write-Host "hunt health: $((Invoke-WebRequest http://127.0.0.1:8788/v1/health -UseBasicParsing).StatusCode)" } catch { Write-Host "hunt health: fail" }
try { Write-Host "console: $((Invoke-WebRequest http://127.0.0.1:5173/ -UseBasicParsing).StatusCode)" } catch { Write-Host "console: fail" }
