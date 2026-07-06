#!/usr/bin/env bash
set -euo pipefail

# Set this to the GGUF file to serve. Relative paths are resolved from this directory.
GGUF_FILE="${GGUF_FILE:-Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf}"
MODEL="${MODEL:-${GGUF_FILE}}"
MMPROJ_FILE="${MMPROJ_FILE:-mmproj-BF16.gguf}"
HF_REPO_ID="${HF_REPO_ID:-unsloth/Qwen3.6-35B-A3B-MTP-GGUF}"
HF_REVISION="${HF_REVISION:-main}"
AUTO_DOWNLOAD="${AUTO_DOWNLOAD:-1}"
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

download_hf_file() {
  local dest_dir="$1"
  local filename="$2"
  local dest="${dest_dir}/${filename}"
  local tmp="${dest}.part"
  local url="https://huggingface.co/${HF_REPO_ID}/resolve/${HF_REVISION}/${filename}"
  local -a curl_args=(-fL --retry 3 --retry-delay 5)

  if [[ -f "${dest}" ]]; then
    return 0
  fi

  mkdir -p "${dest_dir}"

  if [[ -n "${HF_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${HF_TOKEN}")
  fi

  if [[ -f "${tmp}" ]]; then
    echo "Resuming partial download for ${filename}..."
    curl_args+=(-C -)
  else
    echo "Downloading ${filename} to ${dest}..."
  fi

  curl "${curl_args[@]}" -o "${tmp}" "${url}"
  mv -f "${tmp}" "${dest}"
  echo "Saved ${dest}"
}

download_hf_files() {
  local dest_dir="$1"
  shift
  local -a files=("$@")

  command -v curl >/dev/null 2>&1 || {
    echo "error: curl is required to download model files" >&2
    exit 1
  }

  for filename in "${files[@]}"; do
    download_hf_file "${dest_dir}" "${filename}"
  done
}

ensure_model_files() {
  local -a missing=()

  if [[ ! -f "${MODEL}" ]]; then
    missing+=("$(basename "${MODEL}")")
  fi
  if [[ ! -f "${MMPROJ_FILE}" ]]; then
    missing+=("$(basename "${MMPROJ_FILE}")")
  fi

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  if [[ "${AUTO_DOWNLOAD}" == "0" ]]; then
    echo "error: missing model files: ${missing[*]}" >&2
    echo "Download from https://huggingface.co/${HF_REPO_ID} or set AUTO_DOWNLOAD=1" >&2
    exit 1
  fi

  echo "Missing model files: ${missing[*]}"
  echo "Downloading from ${HF_REPO_ID} to ${SCRIPT_DIR}..."
  echo "This may take a while (~40 GB total for the default files)..."

  download_hf_files "${SCRIPT_DIR}" "${missing[@]}"

  if [[ ! -f "${MODEL}" ]]; then
    echo "error: model file still missing after download: ${MODEL}" >&2
    exit 1
  fi
  if [[ ! -f "${MMPROJ_FILE}" ]]; then
    echo "error: mmproj file still missing after download: ${MMPROJ_FILE}" >&2
    exit 1
  fi

  echo "Model files ready in ${SCRIPT_DIR}."
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

echo "Waiting for HTTP readiness at ${READY_URL}"
until curl -fsS "${READY_URL}" >/dev/null 2>&1; do
  if ! kill -0 "${server_pid}" 2>/dev/null; then
    echo "llama-server exited before becoming ready"
    tail -n 200 "${LOG_FILE}" || true
    rm -f "${PID_FILE}"
    exit 1
  fi
  echo "  still starting..."
  sleep 5
done

echo "llama-server is ready"
echo "OpenAI base URL: http://${HOST}:${PORT}/v1"
echo "llama-server is ready and responding; shell is now free."
