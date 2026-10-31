#!/usr/bin/env bash
# Stop Nebula umbrella stack: console, cti-core, hunt, intel, optional peers.
# Default: recorded PIDs + loopback port owners + MISP/postgres compose down.
# Hermes (:8791) only if recorded in pids.env or STOP_FORCE_HERMES=1.
# Idempotent / safe when already stopped. Never prints secrets. Never touches remote hosts.
#
# Env flags:
#   STOP_PIDS_ONLY=1     only kill PIDs from logs/pids.env
#   STOP_LEAVE_DOCKER=1  skip MISP + postgres compose down
#   STOP_FORCE_HERMES=1  also stop :8791 even if not in pids.env
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT/logs/pids.env"
ENV_FILE="$ROOT/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

CTI_ROOT="${CTI_ROOT:-/mnt/c/Users/MOHD/Desktop/Projects/CTI}"
# Windows path in .env → WSL mount
if [[ "$CTI_ROOT" =~ ^[A-Za-z]:\\ ]]; then
  drive="$(echo "${CTI_ROOT:0:1}" | tr '[:upper:]' '[:lower:]')"
  rest="${CTI_ROOT:3}"
  CTI_ROOT="/mnt/${drive}/${rest//'\'//}"
fi

had_hermes_pid=0

stop_pid() {
  local label="$1" pid="$2"
  if [[ -n "${pid:-}" ]]; then
    echo "Stopping $label=$pid"
    kill "$pid" 2>/dev/null || true
    # Give graceful a moment, then force if still alive.
    sleep 0.2
    kill -9 "$pid" 2>/dev/null || true
  fi
}

if [[ -f "$PID_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$PID_FILE"
  stop_pid console_pid "${console_pid:-}"
  stop_pid cti_pid "${cti_pid:-}"
  stop_pid hunt_pid "${hunt_pid:-}"
  stop_pid intel_pid "${intel_pid:-}"
  if [[ -n "${hermes_pid:-}" ]]; then
    had_hermes_pid=1
    stop_pid hermes_pid "$hermes_pid"
  fi
  rm -f "$PID_FILE"
else
  echo "No pids.env — nothing recorded by this umbrella."
fi

port_pids() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
  elif command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | grep -E ":${port}\\b" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | sort -u
  fi
}

stop_port() {
  local port="$1"
  local pid
  for pid in $(port_pids "$port" | sort -u); do
    [[ -n "$pid" ]] || continue
    echo "Stopping pid=$pid on :$port"
    kill "$pid" 2>/dev/null || true
    sleep 0.2
    kill -9 "$pid" 2>/dev/null || true
  done
}

if [[ "${STOP_PIDS_ONLY:-0}" != "1" ]]; then
  for port in 5173 8790 8788 8787; do
    stop_port "$port"
  done
  if [[ "$had_hermes_pid" -eq 1 || "${STOP_FORCE_HERMES:-0}" == "1" ]]; then
    stop_port 8791
  fi
fi

stop_compose_profile() {
  local compose_file="$1" profile="$2" label="$3" env_file="${4:-}"
  if [[ ! -f "$compose_file" ]]; then
    echo "[skip] $label — compose missing: $compose_file"
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "[skip] $label — docker not found"
    return 0
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "[skip] $label — Docker engine not reachable"
    return 0
  fi

  # Placeholders for ${VAR:?} interpolation on down — never echoed.
  export MISP_DB_PASSWORD="${MISP_DB_PASSWORD:-unused-for-down}"
  export MISP_DB_ROOT_PASSWORD="${MISP_DB_ROOT_PASSWORD:-unused-for-down}"
  export MISP_ADMIN_KEY="${MISP_ADMIN_KEY:-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx}"
  export CTI_API_TOKEN="${CTI_API_TOKEN:-unused-for-down}"
  export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-unused-for-down}"

  echo "[..] $label — docker compose --profile $profile down"
  local args=(compose -f "$compose_file")
  if [[ -n "$env_file" && -f "$env_file" ]]; then
    args+=(--env-file "$env_file")
  fi
  args+=(--profile "$profile" down)
  if docker "${args[@]}" >/dev/null 2>&1; then
    echo "[ok] $label down (or already stopped)"
  else
    echo "[warn] $label compose down failed (ignored; idempotent best-effort)"
  fi
}

if [[ "${STOP_PIDS_ONLY:-0}" != "1" && "${STOP_LEAVE_DOCKER:-0}" != "1" ]]; then
  stop_compose_profile \
    "$CTI_ROOT/fixtures/docker-compose.misp.yml" \
    misp \
    "MISP peer (:8443)" \
    "$CTI_ROOT/.env.misp.local"
  stop_compose_profile \
    "$CTI_ROOT/deploy/docker-compose.prod.yml" \
    postgres \
    "Postgres profile" \
    "$CTI_ROOT/.env"
fi

echo "Done."
bash "$ROOT/scripts/status.sh"
