#!/usr/bin/env bash
# Best-effort stop of umbrella-started PIDs.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT/logs/pids.env"

if [[ -f "$PID_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$PID_FILE"
  for var in console_pid cti_pid hunt_pid; do
    pid="${!var:-}"
    if [[ -n "$pid" ]]; then
      echo "Stopping $var=$pid"
      kill "$pid" 2>/dev/null || true
    fi
  done
  rm -f "$PID_FILE"
else
  echo "No pids.env — nothing recorded by this umbrella."
fi

bash "$ROOT/scripts/status.sh"
