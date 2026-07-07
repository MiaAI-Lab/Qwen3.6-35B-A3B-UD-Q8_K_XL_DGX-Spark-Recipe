#!/usr/bin/env bash
set -euo pipefail

cleanup() {
  ./stop.sh || true
}

trap cleanup TERM INT

./start.sh

# Keep the container alive while llama-server runs in the background. The trap
# above lets `docker compose down` stop llama-server cleanly.
tail -F .llama-server.log &
tail_pid="$!"
wait "${tail_pid}"
