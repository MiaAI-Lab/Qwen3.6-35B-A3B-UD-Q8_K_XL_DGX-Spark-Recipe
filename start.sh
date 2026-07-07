#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Hugging Face access token (recommended — set before first run)
# Create at https://huggingface.co/settings/tokens (Read permission is enough)
# Paste your token below, or export HF_TOKEN="hf_..." before running ./start.sh
# ---------------------------------------------------------------------------
HF_TOKEN_KEY=""
HF_TOKEN="${HF_TOKEN:-${HF_TOKEN_KEY}}"
if [[ -n "${HF_TOKEN}" ]]; then
  export HF_TOKEN
fi

# Set this to the GGUF file to serve. Relative paths are resolved from this directory.
GGUF_FILE="${GGUF_FILE:-Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf}"
MODEL="${MODEL:-${GGUF_FILE}}"
MMPROJ_FILE="${MMPROJ_FILE:-mmproj-BF16.gguf}"
HF_REPO_ID="${HF_REPO_ID:-unsloth/Qwen3.6-35B-A3B-MTP-GGUF}"
HF_REVISION="${HF_REVISION:-main}"
AUTO_DOWNLOAD="${AUTO_DOWNLOAD:-1}"
USE_HF_DOWNLOAD="${USE_HF_DOWNLOAD:-0}"
LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-}"
LLAMA_SERVER_PATHS="${LLAMA_SERVER_PATHS:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOST="0.0.0.0"
PORT="8888"
PID_FILE="${SCRIPT_DIR}/.llama-server.pid"
LOG_FILE="${SCRIPT_DIR}/.llama-server.log"
READY_URL="http://127.0.0.1:${PORT}/health"

if [[ "${MODEL}" != /* ]]; then
  MODEL="${SCRIPT_DIR}/${MODEL}"
fi

if [[ "${MMPROJ_FILE}" != /* ]]; then
  MMPROJ_FILE="${SCRIPT_DIR}/${MMPROJ_FILE}"
fi

hf_download_file() {
  local current_path="$1"
  local filename
  local hf_output
  local resolved_path

  if [[ "${USE_HF_DOWNLOAD}" != "1" && -f "${current_path}" ]]; then
    echo "${current_path}"
    return 0
  fi

  command -v hf >/dev/null 2>&1 || {
    echo "error: hf CLI is required to download model files" >&2
    echo "Install with: pip install -U 'huggingface_hub[cli]'" >&2
    exit 1
  }

  filename="$(basename "${current_path}")"
  echo "Downloading ${filename} from ${HF_REPO_ID} with hf download..." >&2
  hf_output="$(hf download "${HF_REPO_ID}" "${filename}" --revision "${HF_REVISION}")"
  resolved_path="${hf_output}"

  if [[ ! -f "${resolved_path}" ]]; then
    while IFS= read -r line; do
      line="${line#  path: }"
      if [[ -f "${line}" ]]; then
        resolved_path="${line}"
        break
      fi
    done <<<"${hf_output}"
  fi

  if [[ ! -f "${resolved_path}" ]]; then
    echo "error: hf download did not return a file path for ${filename}: ${hf_output}" >&2
    exit 1
  fi

  echo "${resolved_path}"
}

ensure_model_files() {
  local -a missing_paths=()

  if [[ "${USE_HF_DOWNLOAD}" == "1" || ! -f "${MODEL}" ]]; then
    missing_paths+=("${MODEL}")
  fi
  if [[ "${USE_HF_DOWNLOAD}" == "1" || ! -f "${MMPROJ_FILE}" ]]; then
    missing_paths+=("${MMPROJ_FILE}")
  fi

  if [[ ${#missing_paths[@]} -eq 0 ]]; then
    echo "Model files already present — skipping download."
    echo "  model:  ${MODEL}"
    echo "  mmproj: ${MMPROJ_FILE}"
    return 0
  fi

  if [[ "${AUTO_DOWNLOAD}" == "0" ]]; then
    echo "error: missing model files: ${missing_paths[*]}" >&2
    echo "Download from https://huggingface.co/${HF_REPO_ID} or set AUTO_DOWNLOAD=1" >&2
    exit 1
  fi

  echo "Missing model files: ${missing_paths[*]}"
  echo "Downloading from ${HF_REPO_ID} into the Hugging Face cache..."
  echo "This may take a while (~40 GB total for the default files)..."

  if [[ -z "${HF_TOKEN}" ]]; then
    echo "warning: HF_TOKEN is not set — downloads may be slow or rate-limited."
    echo "         Set HF_TOKEN_KEY at the top of start.sh or export HF_TOKEN before running."
  fi

  MODEL="$(hf_download_file "${MODEL}")"
  MMPROJ_FILE="$(hf_download_file "${MMPROJ_FILE}")"

  if [[ ! -f "${MODEL}" ]]; then
    echo "error: model file still missing after download: ${MODEL}" >&2
    exit 1
  fi
  if [[ ! -f "${MMPROJ_FILE}" ]]; then
    echo "error: mmproj file still missing after download: ${MMPROJ_FILE}" >&2
    exit 1
  fi

  echo "Model files ready."
  echo "  model:  ${MODEL}"
  echo "  mmproj: ${MMPROJ_FILE}"
}

server_load_status() {
  local tail_log=""

  [[ -f "${LOG_FILE}" ]] || {
    echo "starting"
    return
  }

  tail_log="$(tail -n 80 "${LOG_FILE}" 2>/dev/null || true)"

  if grep -q "server is listening" <<<"${tail_log}"; then
    echo "listening"
  elif grep -q "model loaded" <<<"${tail_log}"; then
    echo "model loaded"
  elif grep -q "warming up" <<<"${tail_log}"; then
    echo "warming up"
  elif grep -q "speculative decoding context initialized" <<<"${tail_log}"; then
    echo "speculative decode ready"
  elif grep -q "loaded multimodal model" <<<"${tail_log}"; then
    echo "vision model loaded"
  elif grep -q "load_model: loading model" <<<"${tail_log}"; then
    echo "loading weights"
  else
    echo "starting"
  fi
}

wait_for_server_ready() {
  local server_pid="$1"
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0 elapsed=0 interval=2 status spin_char

  while ! curl -fsS "${READY_URL}" >/dev/null 2>&1; do
    if ! kill -0 "${server_pid}" 2>/dev/null; then
      printf '\n' >&2
      echo "llama-server exited before becoming ready"
      tail -n 200 "${LOG_FILE}" || true
      rm -f "${PID_FILE}"
      exit 1
    fi

    status="$(server_load_status)"
    spin_char="${spin:$((i % ${#spin})):1}"
    i=$((i + 1))
    printf '\r\033[Kllama-server %s  %02d:%02d  %s' \
      "${spin_char}" $((elapsed / 60)) $((elapsed % 60)) "${status}" >&2
    sleep "${interval}"
    elapsed=$((elapsed + interval))
  done

  printf '\r\033[K' >&2
  if [[ "${elapsed}" -gt 0 ]]; then
    echo "llama-server ready in $((elapsed / 60))m $((elapsed % 60))s"
  else
    echo "llama-server ready"
  fi
}

command -v curl >/dev/null 2>&1 || {
  echo "curl is not on PATH"
  exit 1
}

ensure_model_files

if [[ -z "${LLAMA_SERVER_BIN}" ]]; then
  if command -v llama-server >/dev/null 2>&1; then
    LLAMA_SERVER_BIN="$(command -v llama-server)"
  else
    search_paths=()
    if [[ -n "${LLAMA_SERVER_PATHS}" ]]; then
      IFS=':' read -r -a search_paths <<< "${LLAMA_SERVER_PATHS}"
    else
      search_paths=(
      "${SCRIPT_DIR}/build/bin/llama-server" \
      "${SCRIPT_DIR}/../build/bin/llama-server" \
      "${SCRIPT_DIR}/../../build/bin/llama-server" \
      "${SCRIPT_DIR}/llama-server" \
      "${SCRIPT_DIR}/../llama-server" \
      "${SCRIPT_DIR}/../../llama-server" \
      "${HOME}/llama.cpp/build/bin/llama-server" \
      "${HOME}/build/bin/llama-server" \
      "${HOME}/llama-server" \
      "${HOME}/bin/llama-server"
      )
    fi

    for candidate in "${search_paths[@]}"; do
      if [[ -x "${candidate}" ]]; then
        LLAMA_SERVER_BIN="${candidate}"
        break
      fi
    done

    if [[ -z "${LLAMA_SERVER_BIN}" && -d "${HOME}" ]]; then
      found_bin="$(find "${HOME}" -maxdepth 4 -type f -name llama-server -perm -u+x 2>/dev/null | head -n 1 || true)"
      if [[ -n "${found_bin}" ]]; then
        LLAMA_SERVER_BIN="${found_bin}"
      fi
    fi

    if [[ -z "${LLAMA_SERVER_BIN}" ]]; then
      echo "error: llama-server not found; set LLAMA_SERVER_BIN or put llama-server in PATH" >&2
      exit 1
    fi
  fi
fi

if [[ -f "${PID_FILE}" ]]; then
  pid="$(cat "${PID_FILE}")"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    if curl -fsS "${READY_URL}" >/dev/null 2>&1; then
      echo "llama-server is already running (pid ${pid})"
      echo "Log: ${LOG_FILE}"
      exit 0
    fi
    echo "Stopping stale llama-server process ${pid}"
    kill "${pid}" 2>/dev/null || true
  fi
  rm -f "${PID_FILE}"
fi

echo "Starting llama-server for ${MODEL}"
echo "Listening on ${HOST}:${PORT}"
echo "Writing progress to ${LOG_FILE}"

cat >"${LOG_FILE}" <<EOF
[$(date -Is)] launching llama-server
EOF

nohup "${LLAMA_SERVER_BIN}" \
  --model "${MODEL}" \
  --mmproj "${MMPROJ_FILE}" \
  --ctx-size 262144 \
  --host "${HOST}" \
  --port "${PORT}" \
  --temperature 0.6 \
  --top-p 0.95 \
  --top-k 20 \
  --min-p 0.0 \
  --presence-penalty 0.0 \
  --repeat-penalty 1.0 \
  --chat-template-kwargs '{"preserve_thinking":true}' \
  --spec-type draft-mtp \
  --spec-draft-n-max 6 \
  --spec-draft-p-min 0.85 \
  >>"${LOG_FILE}" 2>&1 &

server_pid=$!
echo "${server_pid}" >"${PID_FILE}"
echo "Spawned llama-server (pid ${server_pid})"

wait_for_server_ready "${server_pid}"
echo "OpenAI base URL: http://${HOST}:${PORT}/v1"
