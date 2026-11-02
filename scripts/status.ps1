# Print which stack ports are listening and probe health (no secrets).
$ErrorActionPreference = "Continue"

$checks = @(
  @{ Name = "cti-console"; Port = 5173; Url = "http://127.0.0.1:5173/";        SkipTls = $false }
  @{ Name = "cti-core";    Port = 8790; Url = "http://127.0.0.1:8790/health";  SkipTls = $false }
  @{ Name = "hunt-api";    Port = 8788; Url = "http://127.0.0.1:8788/v1/health"; SkipTls = $false }
  @{ Name = "intel-core";  Port = 8787; Url = "http://127.0.0.1:8787/v1/health"; SkipTls = $false }
  @{ Name = "misp-peer";   Port = 8443; Url = "https://127.0.0.1:8443/";       SkipTls = $true }
  @{ Name = "hermes-mcp";  Port = 8791; Url = "http://127.0.0.1:8791/";        SkipTls = $false }
)

foreach ($c in $checks) {
  $listen = Get-NetTCPConnection -LocalPort $c.Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  $listenPart = if ($listen) { "LISTEN pid=$($listen.OwningProcess)" } else { "down" }
  $health = "n/a"
  try {
    if ($c.SkipTls) {
      # Local MISP self-signed — probe with curl.exe when available.
      if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        $code = & curl.exe -sk -o NUL -w "%{http_code}" --connect-timeout 3 --max-time 5 $c.Url 2>$null
        if ($code -and $code -ne "000") { $health = "HTTP $code" } else { $health = "fail" }
      } else {
        $health = "skip-tls"
      }
    } else {
      $r = Invoke-WebRequest -Uri $c.Url -UseBasicParsing -TimeoutSec 3
      $health = "HTTP $($r.StatusCode)"
    }
  } catch {
    $code = $null
    try { $code = [int]$_.Exception.Response.StatusCode } catch { }
    if ($code) { $health = "HTTP $code" } else { $health = "fail" }
  }
  Write-Host ("{0,-12} :{1}  {2,-22}  {3}" -f $c.Name, $c.Port, $listenPart, $health)
}
