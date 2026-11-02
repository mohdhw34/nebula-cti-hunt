#!/usr/bin/env bash
# Start (or reuse) intel-core :8787 + hunt-api :8788 + cti-core :8790 + cti-console :5173
# + Hermes MCP HTTP :8791 (required peer; CTI leaf scripts/hermes-mcp.*).
# Loads umbrella .env into this process only. Never prints secret values.
# Does not write into leaf working trees. Loopback only — never remote soak hosts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
LOG_DIR="$ROOT/logs"
PID_FILE="$LOG_DIR/pids.env"
mkdir -p "$LOG_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — copy .env.example to .env and set paths/tokens." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

CTI_ROOT="${CTI_ROOT:-/mnt/c/Users/MOHD/Desktop/Projects/CTI}"
HUNT_ROOT="${HUNT_ROOT:-/mnt/c/Users/MOHD/hunt-platform}"
HERMES_PORT="${HERMES_PORT:-8791}"
# Windows paths in .env → convert for WSL if needed
if [[ "$CTI_ROOT" =~ ^[A-Za-z]:\\ ]]; then
  drive="$(echo "${CTI_ROOT:0:1}" | tr '[:upper:]' '[:lower:]')"
  rest="${CTI_ROOT:3}"
  CTI_ROOT="/mnt/${drive}/${rest//'\'//}"
fi
if [[ "$HUNT_ROOT" =~ ^[A-Za-z]:\\ ]]; then
  drive="$(echo "${HUNT_ROOT:0:1}" | tr '[:upper:]' '[:lower:]')"
  rest="${HUNT_ROOT:3}"
  HUNT_ROOT="/mnt/${drive}/${rest//'\'//}"
fi

[[ -d "$CTI_ROOT" ]] || { echo "CTI_ROOT not found: $CTI_ROOT" >&2; exit 1; }
[[ -d "$HUNT_ROOT" ]] || { echo "HUNT_ROOT not found: $HUNT_ROOT" >&2; exit 1; }

export VITE_HUNT_TOKEN="${VITE_HUNT_TOKEN:-${NEBULA_HUMAN_TOKEN:-}}"
export VITE_HUNT_API_URL="${VITE_HUNT_API_URL:-http://127.0.0.1:8788}"
export VITE_HUNT_PLATFORM_URL="${VITE_HUNT_PLATFORM_URL:-http://127.0.0.1:8788}"
export HUNT_PLATFORM_URL="${HUNT_PLATFORM_URL:-http://127.0.0.1:8788}"
export INTEL_CORE_URL="${INTEL_CORE_URL:-http://127.0.0.1:8787}"
export HUNT_PLATFORM_TOKEN="${HUNT_PLATFORM_TOKEN:-${NEBULA_HUMAN_TOKEN:-}}"
export HUNT_NO_SECRETS="${HUNT_NO_SECRETS:-1}"
export CTI_CORE_URL="${CTI_CORE_URL:-http://127.0.0.1:8790}"
export HERMES_PERMISSION="${HERMES_PERMISSION:-read_only}"
# HTTP transport requires Bearer; mint ephemeral local soak token if unset (never printed).
if [[ -z "${HERMES_AGENT_TOKEN:-}" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    HERMES_AGENT_TOKEN="$(openssl rand -base64 32 | tr -d '\n')"
  else
    HERMES_AGENT_TOKEN="$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
  fi
  export HERMES_AGENT_TOKEN
  echo "[..] HERMES_AGENT_TOKEN unset - minted ephemeral local soak token (not printed; set in .env to persist)"
fi

port_up() { ss -ltn 2>/dev/null | grep -q ":$1 " || netstat -ltn 2>/dev/null | grep -q ":$1 "; }

wait_port() {
  local p="$1" n="${2:-30}"
  for _ in $(seq 1 "$n"); do
    port_up "$p" && return 0
    sleep 0.4
  done
  port_up "$p"
}

: > "$PID_FILE"

if port_up 8787 && port_up 8788; then
  echo "[ok] intel-core already on :8787"
  echo "[ok] hunt-api already on :8788"
elif [[ "${NEBULA_REUSE_ONLY:-0}" == "1" ]]; then
  echo "[warn] NEBULA_REUSE_ONLY=1 and hunt ports down" >&2
else
  echo "[..] starting hunt stack (intel :8787 + hunt-api :8788)"
  (
    cd "$HUNT_ROOT"
    HUNT_NO_SECRETS="$HUNT_NO_SECRETS" ./scripts/dev.sh
  ) >"$LOG_DIR/hunt.out.log" 2>"$LOG_DIR/hunt.err.log" &
  echo "hunt_pid=$!" >>"$PID_FILE"
  wait_port 8787 40 || true
  wait_port 8788 40 || true
fi

if port_up 8790; then
  echo "[ok] cti-core already on :8790"
elif [[ "${NEBULA_REUSE_ONLY:-0}" == "1" ]]; then
  echo "[warn] NEBULA_REUSE_ONLY=1 and :8790 down" >&2
else
  echo "[..] starting cti-core :8790"
  (
    cd "$CTI_ROOT/services/cti-core"
    export PYTHONPATH="$CTI_ROOT/services/cti-core/src"
    export CTI_HOST=127.0.0.1 CTI_PORT=8790
    if [[ -d .venv ]]; then
      # shellcheck disable=SC1091
      source .venv/bin/activate
    fi
    python -m uvicorn cti_core.main:app --host 127.0.0.1 --port 8790
  ) >"$LOG_DIR/cti.out.log" 2>"$LOG_DIR/cti.err.log" &
  echo "cti_pid=$!" >>"$PID_FILE"
  wait_port 8790 30 || true
fi

if port_up 5173; then
  echo "[ok] console already on :5173"
elif [[ "${NEBULA_REUSE_ONLY:-0}" == "1" ]]; then
  echo "[warn] NEBULA_REUSE_ONLY=1 and :5173 down" >&2
else
  echo "[..] starting cti-console :5173 (env from umbrella .env, no leaf writes)"
  (
    cd "$CTI_ROOT/apps/cti-console"
    [[ -d node_modules ]] || npm install
    npm run dev -- --host 127.0.0.1 --port 5173 --strictPort
  ) >"$LOG_DIR/console.out.log" 2>"$LOG_DIR/console.err.log" &
  echo "console_pid=$!" >>"$PID_FILE"
  wait_port 5173 45 || true
fi

# Hermes MCP HTTP (required) — CTI leaf scripts/hermes-mcp.sh; loopback only
if port_up "$HERMES_PORT"; then
  echo "[ok] Hermes MCP already on :$HERMES_PORT"
elif [[ "${NEBULA_REUSE_ONLY:-0}" == "1" ]]; then
  echo "[warn] NEBULA_REUSE_ONLY=1 and :$HERMES_PORT down" >&2
else
  hermes_sh="$CTI_ROOT/scripts/hermes-mcp.sh"
  if [[ ! -f "$hermes_sh" ]]; then
    echo "Hermes required but missing CTI script: $hermes_sh" >&2
    exit 1
  fi
  if ! port_up 8790; then
    echo "[warn] cti-core :8790 not listening yet - Hermes will start anyway" >&2
  fi
  echo "[..] starting Hermes MCP HTTP :$HERMES_PORT via CTI scripts/hermes-mcp.sh"
  chmod +x "$hermes_sh" 2>/dev/null || true
  (
    cd "$CTI_ROOT"
    ./scripts/hermes-mcp.sh http "$HERMES_PORT"
  ) >"$LOG_DIR/hermes.out.log" 2>"$LOG_DIR/hermes.err.log" &
  echo "hermes_pid=$!" >>"$PID_FILE"
  wait_port "$HERMES_PORT" 30 || echo "[warn] Hermes did not bind :$HERMES_PORT within timeout - check logs/hermes.err.log" >&2
fi

echo ""
echo "Access URLs (loopback):"
echo "  Console   http://127.0.0.1:5173"
echo "  cti-core  http://127.0.0.1:8790/health"
echo "  hunt-api  http://127.0.0.1:8788/v1/health"
echo "  intel     http://127.0.0.1:8787/v1/health"
echo "  Hermes    http://127.0.0.1:${HERMES_PORT}/health"
echo "Logs: $LOG_DIR"
bash "$ROOT/scripts/status.sh"
