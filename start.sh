#!/usr/bin/env bash
# One-command product run (bash/WSL). Prefer reusing live listeners.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT/scripts/start-stack.sh"
