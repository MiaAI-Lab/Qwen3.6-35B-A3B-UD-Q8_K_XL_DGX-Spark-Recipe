# Qwen3.6-35B-A3B GGUF — llama-server starter

Bash scripts to start and stop [`llama-server`](https://github.com/ggml-org/llama.cpp) from [llama.cpp](https://github.com/ggml-org/llama.cpp) for [Qwen3.6-35B-A3B](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF) GGUF weights.

Designed for **NVIDIA DGX Spark** and other rigs with **96–128 GB VRAM**, where the default Q8_K_XL quant and 256K context window can run comfortably.

It handles binary detection, prevents duplicate instances, waits for the server to become healthy, and keeps everything running in the background even after you close the terminal.

<p>
<a href="https://x.com/MiaAI_lab" target="_blank">
  <img src="https://img.shields.io/badge/Follow%20me%20on%20X-000000?style=for-the-badge&logo=x&logoColor=white" alt="Follow Mia on X" />
</a>
</p>
<p>
<a href='https://ko-fi.com/Z8Z3SPLOD' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi6.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>
</p>

## Model & Architecture

| Property | Value |
|---|---|
| **Base model** | [Qwen3.6-35B-A3B](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF) — MoE architecture |
| **Quantization** | UD-Q8_K_XL (Unsloth Dynamic, ~39 GB on disk) |
| **MTP** | Multi-Token Prediction heads baked into the GGUF; used for speculative decoding |
| **Vision** | Qwen-VL multimodal via `mmproj-BF16.gguf` (~903 MB) |
| **Thinking / CoT** | Enabled via `--chat-template-kwargs '{"preserve_thinking":true}'` |
| **Context window** | 262 144 tokens (256K) per slot |

The default recipe targets a single-GPU setup. On DGX Spark (NVIDIA GB10, ~128 GB unified memory), `llama-server` auto-fits layers and KV cache to available VRAM (`-fit on` by default, `gpu_layers=-1`).

## Features

- Automatic `llama-server` binary detection (`PATH`, `./build/bin/llama-server`, or `./llama-server`)
- PID file management and cleanup of stale processes
- Health check polling (`/health` endpoint) before declaring ready
- Persistent logging and background execution via `nohup`
- Simple GGUF file setting at the top of `start.sh`
- Automatic model download from Hugging Face when `.gguf` files are missing
- OpenAI-compatible API ready (`/v1` endpoint)
- Companion `stop.sh` script for graceful shutdown

## Requirements

| Requirement | Notes |
|---|---|
| **OS** | Linux (bash, `nohup`, `pgrep`, `kill`) — WSL works; native Windows does not |
| **GPU / VRAM** | **96–128 GB VRAM** recommended (tested on DGX Spark / GB10). The ~40 GB weight file is only part of the footprint — 256K context, mmproj, MTP draft context, and 4 parallel slots need substantially more |
| **CUDA build of llama.cpp** | `llama-server` compiled with CUDA for your architecture (e.g. Blackwell sm_121 on Spark, or sm_80+ on datacenter GPUs) |
| **llama.cpp version** | Recent `master` or nightly — must support `--mmproj`, `--spec-type draft-mtp`, and `--chat-template-kwargs` |
| **Tools** | `bash`, `curl` |
| **Hugging Face token** | **Recommended** — set `HF_TOKEN_KEY` in `start.sh` or `export HF_TOKEN` before running; improves download speed and avoids rate limits |
| **Disk** | ~40 GB free for model downloads + space for `.llama-server.log` |

### Building llama.cpp

The repo does **not** ship a `llama-server` binary. Build from source on each target machine:

```bash
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
cmake -B build -DGGML_CUDA=ON
cmake --build build --config Release -j"$(nproc)"
# binary at: build/bin/llama-server
```

Then either add it to `PATH`, symlink it next to the scripts, or pass `LLAMA_SERVER_BIN`:

```bash
LLAMA_SERVER_BIN=~/llama.cpp/build/bin/llama-server ./start.sh
```

The start script searches, in order: `PATH` → `LLAMA_SERVER_PATHS` → `./build/bin/llama-server` → `./llama-server` → `~/llama.cpp/build/bin/llama-server` → a shallow `find` under `$HOME`.

## Model Files

This repo does **not** include the model weights. `start.sh` will **automatically download** any missing files from [unsloth/Qwen3.6-35B-A3B-MTP-GGUF](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF) on first run, writing them **directly into the script directory** (not the Hugging Face cache). Uses `curl` with resume support for interrupted downloads.

A [Hugging Face access token](https://huggingface.co/settings/tokens) is **recommended** before the first run — set `HF_TOKEN_KEY` at the top of `start.sh` or export `HF_TOKEN` in your shell. This avoids rate limits on large (~40 GB) downloads.

On every run, `start.sh` checks whether both `.gguf` files already exist in the script directory. If they do, the download step is **skipped entirely**. If only one is missing, only that file is downloaded.

You can also download them manually and place them in the same directory as `start.sh`:

| File | Size | Purpose |
|------|------|---------|
| `Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf` | ~39 GB | Main language model |
| `mmproj-BF16.gguf` | ~903 MB | Vision / multimodal projector |

### Download with Hugging Face CLI

```bash
pip install -U huggingface_hub

huggingface-cli download unsloth/Qwen3.6-35B-A3B-MTP-GGUF \
  Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf \
  mmproj-BF16.gguf \
  --local-dir .
```

Or download manually from the [Hugging Face repo](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF).

## Quick Start

```bash
# 1. Make the scripts executable
chmod +x start.sh stop.sh

# 2. Set your Hugging Face token (recommended)
#    Option A — edit start.sh:  HF_TOKEN_KEY="hf_xxxxxxxx"
#    Option B — export in shell:
export HF_TOKEN="hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# 3. Start the server (downloads model files into this directory if missing)
./start.sh
```

## Docker Compose

This repo includes a Docker Compose setup that builds a CUDA 13-enabled `llama-server` from `llama.cpp`, mounts this repo into the container, and stores downloaded `.gguf` files in your host Hugging Face cache.

Requirements:

- Docker with Compose v2
- NVIDIA driver and NVIDIA Container Toolkit configured on the host
- A GPU/VRAM setup suitable for this model, as described above

Create a local environment file and set your Hugging Face token:

```bash
cp .env.example .env
# edit .env and set HF_TOKEN=hf_...
```

By default, Compose mounts your host Hugging Face cache at `${HOME}/.cache/huggingface` into the container as `/root/.cache/huggingface`. Missing model files are downloaded with `hf download`, so Hugging Face stores them under its normal hub cache layout:

```text
${HOME}/.cache/huggingface/hub/
```

To use a different host cache directory, set `HF_CACHE_DIR` in `.env`.

Build and run:

```bash
docker compose up --build -d
docker compose logs -f qwen-spark
```

The first run downloads the model files into the mounted Hugging Face hub cache unless they already exist. `start.sh` uses the snapshot paths returned by `hf download` when launching `llama-server`. The OpenAI-compatible base URL is:

```text
http://localhost:8888/v1
```

Stop the server:

```bash
docker compose down
```

DGX Spark / GB10 uses CUDA architecture `121`. If you are on a different GPU, set the CUDA architecture before building. For example:

```bash
CMAKE_CUDA_ARCHITECTURES=90 docker compose build
```

To skip auto-download and fail fast if files are missing:

```bash
AUTO_DOWNLOAD=0 ./start.sh
```

Once it says **"llama-server is ready"**, you can use the OpenAI-compatible endpoint:

```
http://localhost:8888/v1
```

### Test the API

```bash
# Health check
curl http://127.0.0.1:8888/health

# List models
curl http://127.0.0.1:8888/v1/models

# Chat completion
curl -s http://127.0.0.1:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}],
    "temperature": 0.6,
    "max_tokens": 128
  }'
```

Available endpoints follow the [llama.cpp server API](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md): `/v1/chat/completions`, `/v1/completions`, `/v1/models`, `/health`.

### Stopping the Server

```bash
./stop.sh
```

This gracefully stops the running server, waits for clean shutdown, and removes the PID file. If the PID file is missing or stale, it falls back to finding the matching `llama-server` for this model on port `8888`.

## Configuration

### GGUF Files

Set the model and multimodal projector files at the top of `start.sh`:

```bash
GGUF_FILE="${GGUF_FILE:-Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf}"
MMPROJ_FILE="${MMPROJ_FILE:-mmproj-BF16.gguf}"
```

Relative paths are resolved from the directory containing `start.sh`.

You can also override the files for one run without editing the script:

```bash
GGUF_FILE=other-model.gguf MMPROJ_FILE=other-mmproj.gguf ./start.sh
```

The older `MODEL` override still works and takes priority over `GGUF_FILE`:

```bash
MODEL=llama-3.1-70b-Q4_K_M.gguf ./start.sh
```

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `GGUF_FILE` | `Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf` | Main model weights |
| `MMPROJ_FILE` | `mmproj-BF16.gguf` | Vision projector |
| `MODEL` | same as `GGUF_FILE` | Legacy override; takes priority over `GGUF_FILE` |
| `LLAMA_SERVER_BIN` | auto-detected | Path to `llama-server` binary |
| `LLAMA_SERVER_PATHS` | built-in list | Colon-separated extra search paths |
| `HF_REPO_ID` | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF` | Hugging Face repo used for auto-download |
| `HF_REVISION` | `main` | Branch, tag, or commit for download URL |
| `AUTO_DOWNLOAD` | `1` | Download missing `.gguf` files on start (`0` to disable) |
| `HF_TOKEN_KEY` | `""` (in `start.sh`) | Paste your Hugging Face token here (recommended) |
| `HF_TOKEN` | falls back to `HF_TOKEN_KEY` | Env override; export before running takes precedence |

### Other Settings (edit `start.sh`)

| Setting | Default | Description |
|---|---|---|
| `HOST` | `0.0.0.0` | Bind address (all interfaces) |
| `PORT` | `8888` | HTTP port — must match in `stop.sh` too |
| `PID_FILE` | `.llama-server.pid` | Written on start, removed on stop |
| `LOG_FILE` | `.llama-server.log` | Server stdout/stderr |

Example:

```bash
LLAMA_SERVER_BIN=~/llama.cpp/build/bin/llama-server ./start.sh
```

To change the port, edit this line in `start.sh`:

```bash
PORT="8888"
```

### Default Server Parameters

These flags are set in `start.sh` and passed to `llama-server`:

| Flag | Value | Purpose |
|---|---|---|
| `--model` | `Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf` | Main GGUF weights |
| `--mmproj` | `mmproj-BF16.gguf` | Vision / multimodal projector |
| `--ctx-size` | `262144` | 256K context per slot |
| `--host` / `--port` | `0.0.0.0` / `8888` | HTTP bind |
| `--temperature` | `0.6` | Default sampling temperature |
| `--top-p` | `0.95` | Nucleus sampling |
| `--top-k` | `20` | Top-k sampling |
| `--min-p` | `0.0` | Min-p filter |
| `--presence-penalty` | `0.0` | Presence penalty |
| `--repeat-penalty` | `1.0` | Repetition penalty |
| `--chat-template-kwargs` | `{"preserve_thinking":true}` | Keep `<think>` blocks in chat history |
| `--spec-type` | `draft-mtp` | MTP speculative decoding |
| `--spec-draft-n-max` | `6` | Max draft tokens per speculation step |
| `--spec-draft-p-min` | `0.85` | Min draft probability threshold |

**Not set explicitly (llama-server defaults apply):**

| Behavior | Default on CUDA | Notes |
|---|---|---|
| GPU layer offload | `gpu_layers=-1` (all layers) | Auto-fitted to VRAM via `-fit on` |
| Parallel slots | `n_parallel=4` | 4 concurrent requests, each with full context |
| KV cache | unified, per-slot 256K | Major VRAM consumer at long context |
| Prompt cache | 8192 MiB | Enabled automatically by recent llama-server builds |

### Customizing Server Flags

Edit the `nohup` invocation in `start.sh` and restart. Common tuning targets:

- `--ctx-size` — reduce to `131072` or `65536` on tighter VRAM budgets
- `--spec-draft-n-max` / `--spec-draft-p-min` — trade speed vs. acceptance rate
- `-ngl` / `--gpu-layers` — force a specific GPU layer count if auto-fit misbehaves
- `-fit off` — disable auto memory fitting (useful when debugging OOM)
- `--image-min-tokens 1024` — recommended for Qwen-VL grounding accuracy

To use a smaller quant from the same Hugging Face repo (e.g. `Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf` at ~23 GB), download it and override:

```bash
GGUF_FILE=Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf ./start.sh
```

## How It Works

**start.sh** does the following:

1. Checks if a healthy instance is already running and exits early if so
2. Cleans up stale PID files / processes
3. Launches `llama-server` in the background with `nohup`
4. Polls `/health` with a single-line spinner showing elapsed time and load stage (from the log)
5. Prints ready time + OpenAI base URL

**stop.sh** does the following:

1. Reads the PID from `.llama-server.pid`
2. Falls back to the matching `llama-server` process if the PID file is missing, invalid, or stale
3. Sends `SIGTERM` for graceful shutdown
4. Waits up to 15 seconds
5. Force kills with `SIGKILL` only if necessary
6. Cleans up the PID file

**Files created by the scripts:**

- `.llama-server.log` - Server output log
- `.llama-server.pid` - Process ID file

## Recommended Directory Layout

```
./
├── llama-server                        # optional symlink to llama.cpp build
├── start.sh
├── stop.sh
├── README.md
├── Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf    # download from Hugging Face
└── mmproj-BF16.gguf                    # download from Hugging Face
```

`llama-server` can be a binary or a symlink to your llama.cpp build. The script also checks `./build/bin/llama-server` and `PATH`.

## Troubleshooting

**"error: llama-server not found"**

Set the full path explicitly:

```bash
LLAMA_SERVER_BIN=/path/to/llama-server ./start.sh
```

**Server starts but never becomes "ready"**

Check the log:

```bash
tail -n 100 .llama-server.log
```

Common causes: missing model files, out of memory, unsupported flags in your llama.cpp build, or model loading failure.

**"model file not found" or "mmproj not found"**

`start.sh` should auto-download on the next run via `curl`. Partial downloads resume from `*.part` files. If it fails, set `HF_TOKEN_KEY` in `start.sh` (rate limits are common without a token) or download manually from [unsloth/Qwen3.6-35B-A3B-MTP-GGUF](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF). Set `GGUF_FILE` / `MMPROJ_FILE` if using custom paths.

**Slow or failing model downloads**

Set a Hugging Face token before running: edit `HF_TOKEN_KEY="hf_..."` at the top of `start.sh`, or `export HF_TOKEN="hf_..."`. Create a Read token at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens).

**Port already in use**

Edit `PORT` in both `start.sh` and `stop.sh`, then start the server again.

The default port is `8888`.

**CUDA OOM or "fitting params to device memory" failure**

VRAM is insufficient for the current config. Try, in order:

1. Lower `--ctx-size` (e.g. `131072`, `65536`)
2. Switch to a smaller quant (`Q4_K_XL`, `Q5_K_XL`, etc.) from the [same HF repo](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF)
3. Add `-fit off` and set `-ngl` manually to partial GPU offload
4. Reduce parallel slots by adding `--parallel 1` to the `nohup` line

**Unknown flag / unsupported feature errors**

Your `llama-server` build is too old. Rebuild from current llama.cpp `master` with `-DGGML_CUDA=ON`.

**Vision accuracy issues on grounding tasks**

Add `--image-min-tokens 1024` to the server flags. Qwen-VL models expect at least 1024 image tokens for reliable grounding ([llama.cpp #16842](https://github.com/ggml-org/llama.cpp/issues/16842)).

## Running on Other Machines

The scripts are portable Linux bash — no DGX-specific paths or hardcoded hostnames. However, the **default configuration is not one-size-fits-all**:

| Scenario | Will it work out of the box? |
|---|---|
| DGX Spark / 96–128 GB VRAM + CUDA llama.cpp | Yes, after downloading models and building `llama-server` |
| x86_64 Linux with 96+ GB VRAM | Yes, with a CUDA build compiled for that GPU architecture |
| 48 GB GPU (e.g. RTX 6000) | Unlikely — reduce `--ctx-size`, use a smaller quant, or lower `n_parallel` |
| CPU-only | No — model is far too large for practical CPU inference |
| Different CPU arch (arm64 vs x86_64) | Script yes, binary no — rebuild llama.cpp per platform |

The script does **not** set `-ngl` / `--gpu-layers`; it relies on llama-server's CUDA auto-fit. On non-CUDA builds the server will attempt CPU inference and fail or hang on a 39 GB model.

## Compatibility

- **llama.cpp**: recent build with CUDA, MTP (`draft-mtp`), multimodal (`mmproj`), and Qwen3 chat template support
- **GPU**: NVIDIA CUDA; tested on GB10 (Blackwell, sm_121, ARM64 host)
- **OS**: modern Linux with `bash`, `curl`, and standard process utilities (`pgrep`, `kill`, `nohup`)

## License

MIT

---

Made for convenient local LLM serving with llama.cpp.
