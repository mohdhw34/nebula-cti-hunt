#!/usr/bin/env bash
# Print which stack ports are listening and probe health (no secrets).
set -u

check() {
  local name="$1" port="$2" url="$3" insecure="${4:-0}"
  local listen="down" health="fail"
  if ss -ltn 2>/dev/null | grep -q ":${port} " || netstat -ltn 2>/dev/null | grep -q ":${port} "; then
    listen="LISTEN"
  fi
  local curl_opts=(-s -o /dev/null -w '%{http_code}' --max-time 3)
  if [[ "$insecure" == "1" ]]; then
    curl_opts+=(-k)
  fi
  code="$(curl "${curl_opts[@]}" "$url" || true)"
  if [[ -n "$code" && "$code" != "000" ]]; then
    health="HTTP $code"
  fi
  printf '%-12s :%-5s %-10s %s\n' "$name" "$port" "$listen" "$health"
}

check cti-console 5173 "http://127.0.0.1:5173/"
check cti-core    8790 "http://127.0.0.1:8790/health"
check hunt-api    8788 "http://127.0.0.1:8788/v1/health"
check intel-core  8787 "http://127.0.0.1:8787/v1/health"
check misp-peer   8443 "https://127.0.0.1:8443/" 1
check hermes-mcp  8791 "http://127.0.0.1:8791/"
