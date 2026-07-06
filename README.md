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


## Features

- Automatic `llama-server` binary detection (`PATH`, `./build/bin/llama-server`, or `./llama-server`)
- PID file management and cleanup of stale processes
- Health check polling (`/health` endpoint) before declaring ready
- Persistent logging and background execution via `nohup`
- Simple GGUF file setting at the top of `start.sh`
- OpenAI-compatible API ready (`/v1` endpoint)
- Companion `stop.sh` script for graceful shutdown

## Requirements

- Linux
- `bash`
- `curl`
- A compiled `llama.cpp` build containing the `llama-server` binary
- **96–128 GB VRAM** (tested on DGX Spark; the default Q8_K_XL model + 256K context needs well beyond the ~40 GB model weight size alone)

## Model Files

This repo does **not** include the model weights. Download these two files from [unsloth/Qwen3.6-35B-A3B-MTP-GGUF](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF) and place them in the same directory as `start.sh`:

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

# 2. Download the model files (see "Model Files" above)

# 3. Start the server
./start.sh
```

Once it says **"llama-server is ready"**, you can use the OpenAI-compatible endpoint:

```
http://localhost:8888/v1
```

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

### Other Settings

| Setting             | Default                                      | How to change |
|---------------------|----------------------------------------------|---------------|
| `LLAMA_SERVER_BIN`  | auto-detected                                | Set environment variable |
| `HOST`              | `0.0.0.0`                                    | Edit `start.sh` |
| `PORT`              | `8888`                                       | Edit `start.sh` |
| `PID_FILE`          | `.llama-server.pid`                          | Edit `start.sh` / `stop.sh` |
| `LOG_FILE`          | `.llama-server.log`                          | Edit `start.sh` |

Example:

```bash
LLAMA_SERVER_BIN=~/llama.cpp/build/bin/llama-server ./start.sh
```

To change the port, edit this line in `start.sh`:

```bash
PORT="8888"
```

### Customizing Server Flags

All `llama-server` flags are defined inside `start.sh` (around the `nohup` line). Common things you might want to change:

- `--ctx-size`
- `--temperature`, `--top-p`, `--top-k`
- Speculative decoding settings (`--spec-type`, `--spec-draft-*`)
- `--chat-template-kwargs`

Just edit the script and restart.

## How It Works

**start.sh** does the following:

1. Checks if a healthy instance is already running and exits early if so
2. Cleans up stale PID files / processes
3. Launches `llama-server` in the background with `nohup`
4. Polls `http://127.0.0.1:8888/health` every 5 seconds until ready
5. Prints the ready message + OpenAI base URL

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

Download the required GGUF files from [unsloth/Qwen3.6-35B-A3B-MTP-GGUF](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF) and place them next to `start.sh`, or set `GGUF_FILE` / `MMPROJ_FILE` to the correct paths.

**Port already in use**

Edit `PORT` in `start.sh`, then start the server again.

The default port is `8888`.

## Compatibility

- Requires a `llama-server` build that supports the flags used in `start.sh`
- Should work on modern Linux distributions with `bash` and `curl`

## License

MIT

---

Made for convenient local LLM serving with llama.cpp.
