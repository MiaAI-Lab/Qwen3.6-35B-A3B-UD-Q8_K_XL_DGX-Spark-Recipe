#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/.llama-server.pid"
PORT="8888"
READY_URL="http://127.0.0.1:${PORT}/health"

find_running_pid() {
  local pid=""

  pid="$(pgrep -f "llama-server .*--port ${PORT}" | head -n 1 || true)"
  if [[ -n "${pid}" ]]; then
    echo "${pid}"
    return 0
  fi

  return 0
}

if [[ ! -f "${PID_FILE}" ]]; then
  pid="$(find_running_pid)"
  if [[ -z "${pid}" ]]; then
    echo "No PID file found — llama-server is not running."
    exit 0
  fi
  echo "No PID file found; found running llama-server (pid ${pid})."
else
  pid="$(cat "${PID_FILE}")"
fi

if [[ ! "${pid}" =~ ^[1-9][0-9]*$ ]]; then
  pid="$(find_running_pid)"
  if [[ -z "${pid}" ]]; then
    echo "Invalid PID file contents (removing stale PID file)"
    rm -f "${PID_FILE}"
    exit 0
  fi
  echo "PID file is invalid; found running llama-server (pid ${pid})."
  rm -f "${PID_FILE}"
fi

if ! kill -0 "${pid}" 2>/dev/null; then
  pid="$(find_running_pid)"
  if [[ -z "${pid}" ]]; then
    if curl -fsS "${READY_URL}" >/dev/null 2>&1; then
      echo "llama-server is running on port ${PORT} but the PID file is stale; removing stale PID file."
      rm -f "${PID_FILE}"
      exit 0
    fi
    echo "llama-server is not running (removing stale PID file)"
    rm -f "${PID_FILE}"
    exit 0
  fi
  echo "PID file is stale; found running llama-server (pid ${pid})."
  rm -f "${PID_FILE}"
fi

echo "Stopping llama-server (pid ${pid})..."

# Try graceful shutdown first (SIGTERM)
kill "${pid}" 2>/dev/null || true

# Wait up to 15 seconds for clean shutdown
for i in {1..15}; do
  if ! kill -0 "${pid}" 2>/dev/null; then
    break
  fi
  sleep 1
done

# Force kill if still alive
if kill -0 "${pid}" 2>/dev/null; then
  echo "Process did not exit gracefully — force killing..."
  kill -9 "${pid}" 2>/dev/null || true
  sleep 1
fi

rm -f "${PID_FILE}"
echo "llama-server stopped successfully."
