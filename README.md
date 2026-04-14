# Local LLM Sandbox

**Hardware:** Windows 10 Pro (22H2) + WSL2 Ubuntu 22.04 + RTX 3070 Ti 8GB  
**Goal:** PoC a fully local, private LLM stack that mirrors what we'd run on a production box (DGX Spark etc.)

---

## Reference

### Architecture

```
Browser / VS Code
      │
      ▼
LiteLLM (port 4000)       ← API gateway, auth, routing
      │
      ▼
vLLM (port 8001)          ← inference engine
      │
      ▼
RTX 3070 Ti (8GB VRAM)   ← model runs here
```

Open WebUI (port 3000) sits on top of LiteLLM as a chat interface.

---

### Prerequisites

#### Windows side
- NVIDIA Game Ready or Studio driver installed (591.44 or later)
- WSL2 enabled with Ubuntu 22.04
- **Do NOT install CUDA separately on Windows** — WSL2 handles it via the Windows driver

#### WSL2 Ubuntu side
- systemd enabled (`/etc/wsl.conf` with `[boot] systemd=true`)
- Docker Engine installed natively (not Docker Desktop)
- nvidia-container-toolkit installed and configured
- uv installed (`curl -LsSf https://astral.sh/uv/install.sh | sh`)

---

### First-Time Setup

#### 1. Enable systemd in WSL2
```bash
sudo tee /etc/wsl.conf > /dev/null <<EOF
[boot]
systemd=true
EOF
# Then in PowerShell: wsl --shutdown && wsl
```

#### 2. Install Docker Engine
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable docker && sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker
```

#### 3. Install nvidia-container-toolkit
```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor \
  -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

#### 4. Install uv
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env
```

#### 5. Verify GPU passthrough
```bash
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi
# Should show your RTX 3070 Ti
```

---

### Project Structure

```
~/projects/llm-sandbox/
├── docker-compose.yml      ← all services defined here
├── litellm_config.yaml     ← model routing config
├── .env                    ← HuggingFace token + active model + active quant flag
├── switch-model.sh         ← swap the active model (handles quantization automatically)
├── tmp/
│   ├── pdf_pipeline.py     ← PDF → vision model → JSON pipeline
│   └── sample_scanned.pdf  ← test PDF (scanned government letter)
└── continue/
    └── config.yaml         ← copy to ~/.continue/config.yaml for VS Code
```

---

### Day-to-Day Commands

```bash
# Start
cd ~/projects/llm-sandbox && docker compose up -d

# Stop
docker compose down

# Watch vLLM load (wait for: INFO Application startup complete.)
docker compose logs -f vllm

# Check all containers healthy
docker compose ps

# Switch model (restarts vLLM, takes 2-3 min)
./switch-model.sh code      # Qwen2.5-Coder-7B-AWQ  — copilot + chat
./switch-model.sh chat      # Qwen2.5-7B-AWQ         — general chat
./switch-model.sh vision    # Qwen2-VL-2B            — PDF pipeline
./switch-model.sh gemma4    # Gemma 4 E4B            — testing branch only

# Test API
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-local-master-1234" \
  -d '{"model": "code-assistant", "messages": [{"role": "user", "content": "Hello"}]}'

# Run PDF pipeline
cd ~/projects/llm-sandbox/tmp
uv run --with pymupdf --with openai python pdf_pipeline.py your_file.pdf
```

---

### Access Points

| Service | URL | Notes |
|---|---|---|
| Open WebUI | http://localhost:3000 | Chat interface, connect to http://localhost:4000/v1 |
| LiteLLM API | http://localhost:4000 | OpenAI-compatible, key: `sk-local-master-1234` |
| LiteLLM Admin | http://localhost:4000/ui | Usage dashboard |
| vLLM direct | http://localhost:8001 | Internal only |

---

### Models

| Alias | Model | VRAM | Quantization | Use |
|---|---|---|---|---|
| code-assistant | Qwen/Qwen2.5-Coder-7B-Instruct-AWQ | ~5.5GB | awq_marlin | Copilot + chat |
| chat | Qwen/Qwen2.5-7B-Instruct-AWQ | ~5.5GB | awq_marlin | General chat |
| pdf-vision | Qwen/Qwen2-VL-2B-Instruct | ~3.5GB | none (FP16) | Document extraction |
| gemma4 | google/gemma-4-E4B-it | ~5GB | none (FP16) | Testing branch — too slow on 3070 Ti |

Only one model runs at a time on 8GB VRAM. On the production box all run simultaneously.

---

### Continue.dev Config (`~/.continue/config.yaml`)

Open with `Ctrl+Shift+P` → "Continue: Open config.yaml"

```yaml
name: Local LLM Sandbox
version: 0.0.1
schema: v1

models:
  - name: Local Chat
    provider: openai
    model: chat
    apiBase: http://localhost:4000/v1
    apiKey: sk-local-master-1234
    useLegacyCompletionsEndpoint: false

tabAutocompleteModel:
  name: Local Autocomplete
  provider: openai
  model: code-assistant
  apiBase: http://localhost:4000/v1
  apiKey: sk-local-master-1234
  useLegacyCompletionsEndpoint: false
```

**What works at 7B:**

| Feature | Shortcut | Status | Notes |
|---|---|---|---|
| Chat about code | `Ctrl+L` | ✅ | Add file context with "Active file" toggle |
| Inline edit | `Ctrl+I` | ✅ | Select code first, then describe the change |
| Autocomplete | automatic | ✅ | ~1-2s delay |
| Agent mode | sidebar | ⚠️ | Unreliable at 7B, revisit on production with 32B+ |

---

### vLLM Startup Flags

```yaml
--model ${ACTIVE_MODEL}           # model ID from HuggingFace
--dtype half                      # FP16 (bfloat16 limited on 3070 Ti)
--quantization ${ACTIVE_QUANT}    # injected by switch-model.sh, empty for non-AWQ models
--gpu-memory-utilization 0.85     # 85% of available VRAM (Windows display eats ~1.1GB)
--max-model-len 8192              # max context (17,344 KV cache tokens available)
--max-num-seqs 4                  # max concurrent requests
--enforce-eager                   # disable CUDA graphs, saves ~0.38GB VRAM
# Gemma 4 specific (gemma4-testing branch only):
--enable-auto-tool-choice         # required for agent/tool use
--tool-call-parser gemma4         # Gemma 4 tool call format
--reasoning-parser gemma4         # Gemma 4 reasoning/thinking mode
```

On the production box: remove `--enforce-eager`, remove quantization, increase
`--max-model-len` to 32768+, increase `--max-num-seqs`.

---

### Production Migration Checklist

- [ ] Run multiple vLLM instances on different ports (one per model)
- [ ] Remove `--enforce-eager` and quantization flags
- [ ] Update `api_base` URLs in `litellm_config.yaml`
- [ ] Change `apiBase` in `~/.continue/config.yaml` to production box IP
- [ ] Use Qwen2.5-VL-72B for pdf-vision instead of 2B
- [ ] Test Gemma 4 26B/31B for agent mode on production box

---

### Known Issues

| Issue | Cause | Fix |
|---|---|---|
| `LITELLM_MASTER_KEY not set` warning | Docker compose env var not read | Cosmetic, key is hardcoded in docker-compose.yml |
| `version obsolete` warning | Old compose format | Remove `version: "3.8"` line |
| Model not found 404 | Model name mismatch | Must be `openai/` + exact ID from `curl http://localhost:8001/v1/models` |
| Continue context window error | `--max-model-len` too small | Increase to 8192, restart vLLM |
| Continue empty prompt error | Legacy completions endpoint | Add `useLegacyCompletionsEndpoint: false` to continue config |
| Vision model fails with awq_marlin | Qwen2-VL-2B is not AWQ | switch-model.sh handles this — never hardcode quantization in docker-compose.yml |
| `context_window_fallback_dict` does nothing | Points fallback to same model | No-op — real fix is increasing max-model-len |
| `uv not found` after install | PATH not updated | `source $HOME/.local/bin/env` |
| All containers show healthy but API fails | LiteLLM still running migrations | Wait ~30s after startup for prisma migrate to finish |
| vLLM healthcheck fails on startup | Model load takes longer than start_period | Bump `start_period` to 300s for large models, or run `docker compose up -d litellm open-webui` manually after vLLM is up |
| Gemma 4 fails with `gemma4 architecture not recognized` | vLLM image too old | Use `vllm/vllm-openai:gemma4` image, not `latest` |
| Continue agent mode: `--enable-auto-tool-choice` error | Tool calling not enabled in vLLM | Add `--enable-auto-tool-choice --tool-call-parser gemma4` to vLLM command |

---

## Sessions

---

### 2026-04-12 — Initial Setup

**Goal:** Get the full stack running from scratch on WSL2.

**System state going in:**
- Windows 10 Pro, NVIDIA driver 591.44
- WSL2 Ubuntu 22.04 already initiated but barely configured
- Docker was installed via Docker Desktop but we wanted native Docker Engine in WSL2
- No CUDA toolkit installed in WSL (correct — WSL2 gets it from Windows driver)

**What we did:**
- Confirmed systemd was already running in WSL2 (`ps -p 1` → systemd)
- Removed stale Docker Desktop plugin stubs from `/usr/local/lib/docker/cli-plugins/`
- Installed nvidia-container-toolkit and registered nvidia runtime with Docker
- Verified GPU passthrough with `docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi`
- Fixed ownership of `~/projects` (was owned by root) with `chown -R gakro:gakro`
- Created project structure and all config files
- Got HuggingFace Read token, confirmed Qwen models are not gated (no license agreement needed)
- Brought up the stack — hit two vLLM crashes before it worked:
  - First crash: `gpu_memory_utilization 0.90` requested 7.2GB but only 6.92GB free (Windows display uses ~1.1GB)
  - Second crash: KV cache had no room after model loaded — fixed with `--enforce-eager` and `awq_marlin` quantization
- LiteLLM wouldn't auth — `LITELLM_MASTER_KEY` env var wasn't being passed through docker compose; hardcoded it directly in `docker-compose.yml`
- Model name in litellm_config.yaml had wrong format — needed `openai/Qwen/Qwen2.5-Coder-7B-Instruct-AWQ` (full path with `openai/` prefix)
- Added Postgres container for LiteLLM spend tracking (required for auth to work)
- First successful API response 🎉

**What we learned:**
- Windows display eats ~1.1GB of VRAM — effective VRAM on 3070 Ti is ~6.9GB, not 8GB
- `--quantization awq` is slower than `--quantization awq_marlin` — vLLM even recommends the switch in its own logs
- `--enforce-eager` disables CUDA graph compilation, saving ~0.38GB VRAM at cost of ~10% inference speed
- Docker compose doesn't always interpolate `.env` variables — when in doubt, hardcode
- LiteLLM model name must include `openai/` prefix + exact HuggingFace model ID (check with `curl localhost:8001/v1/models`)
- Open WebUI needs the LiteLLM connection added manually via Manage Connections → http://localhost:4000/v1

---

### 2026-04-13 — Continue.dev + PDF Pipeline

**Goal:** Get IDE copilot working, and prove the PDF extraction pipeline concept.

**Continue.dev:**
- Installed Continue extension in VS Code
- Initial chat attempts failed with "Connection error" — caused by `--max-model-len 4096` being too small for Continue's combined prompt (system prompt + open file + chat history)
- Increased `--max-model-len` to 8192. We have 17,344 KV cache tokens available so there's headroom
- Inline edit (`Ctrl+I`) failed with empty prompt error — Continue was using legacy `/v1/completions` endpoint; fixed with `useLegacyCompletionsEndpoint: false`
- Agent mode attempted but model got stuck in tool-use loops — expected for 7B, skip for now
- Final working workflow: Chat (`Ctrl+L`) for questions, inline edit (`Ctrl+I`) for code changes

**Model switching:**
- `switch-model.sh` originally had no awareness of quantization — switching to vision model passed `--quantization awq_marlin` which Qwen2-VL-2B doesn't support (not an AWQ model)
- Fixed by encoding quantization flag per model inside the script and injecting via `ACTIVE_QUANT` in `.env`
- `docker-compose.yml` command no longer has any hardcoded quantization — all model-specific config lives in the switch script

**PDF pipeline:**
- Installed `uv` for dependency-free Python script execution (no virtualenv management)
- Downloaded a real scanned government letter PDF (8 pages, Missouri Dept of Health) as test case
- Wrote `pdf_pipeline.py`: PyMuPDF renders pages to PNG at 150 DPI → base64 → sent to Qwen2-VL-2B with JSON schema prompt → parsed response
- Results: 7/8 pages extracted successfully with accurate structured data (dates, names, addresses, phone numbers, key points)
- 1 page failed with JSON parse error (model output malformed) — needs retry logic
- Minor issues: occasional schema leakage (model returns schema text instead of null), occasional hallucinated extra fields
- All acceptable for PoC — production box with 72B vision model will be significantly more reliable

**What we learned:**
- `context_window_fallback_dict` pointing to the same model is a no-op — the real fix is always `--max-model-len`
- `--break-system-packages` doesn't exist on Ubuntu 22.04's older pip — use `uv` instead
- Qwen2-VL-2B (2B vision model) handles real scanned documents surprisingly well at this scale
- Quality gap between 2B and 72B on document tasks is qualitative, not just quantitative — tables, handwriting, degraded scans all need the bigger model
- The full pipeline architecture is proven: PDF → image → vision model → JSON works end to end

---

### 2026-04-14 — Gemma 4 Evaluation

**Goal:** Evaluate Google's new Gemma 4 models, particularly for agentic programming with Continue.dev.

**Background:**
- Gemma 4 released April 2, 2026 under Apache 2.0 license
- Built from Gemini 3 research — significant generational leap over Gemma 3
- Benchmark highlights: AIME 2026 31B scores 89.2% (vs Gemma 3 27B at 20.8%), LiveCodeBench 80%, τ2-bench (agentic tool use) 86.4%
- Four sizes: E2B, E4B (edge), 26B MoE (A4B), 31B Dense
- All models have native function calling, reasoning/thinking mode, multimodal support
- Requires `vllm/vllm-openai:gemma4` Docker image (not `latest`) — needs transformers>=5.5.0

**What we did:**
- Added `gemma4` entry to `switch-model.sh` pointing at `google/gemma-4-E4B-it`
- Hit immediate crash with `latest` vLLM image — architecture `gemma4` not recognized
- Switched to `vllm/vllm-openai:gemma4` Docker image — loaded successfully
- E4B ran at ~0.1 tokens/s — completely unusable for testing
- Tried E2B — still too slow on the 3070 Ti
- Root cause: Gemma 4 requires the Triton attention backend (due to heterogeneous head dimensions) which is significantly slower than FlashAttention on consumer GPUs
- No quantized versions of Gemma 4 exist yet (no AWQ/GGUF from Google) — running raw FP16
- Agent mode requires `--enable-auto-tool-choice --tool-call-parser gemma4 --reasoning-parser gemma4` flags
- Isolated Gemma 4 work to a separate git branch (`gemma-4-testing`) for others to evaluate

**What we learned:**
- Gemma 4 is a genuinely impressive model family but the 3070 Ti is not the right hardware for it
- The Triton attention backend requirement is a hard constraint — not a config issue
- E4B is an "effective 4B" model using Per-Layer Embeddings — architecturally clever but still slow without quantization
- The benchmarks that matter for agentic use are for the 26B/31B models, not the E4B
- Production box (DGX Spark, 128GB) is the right place to properly evaluate Gemma 4 — likely 26B MoE which runs at ~4B active parameter speed
- vLLM has dedicated release images for new model families (`:gemma4`, not `:latest`) — check for these when models fail to load

**Gemma 4 on production box (future):**
- Use `google/gemma-4-26B-A4B-it` (MoE, only 4B active parameters — fast inference)
- Or `google/gemma-4-31B-it` for maximum quality
- Add `--enable-auto-tool-choice --tool-call-parser gemma4 --reasoning-parser gemma4` to vLLM command
- Use `vllm/vllm-openai:gemma4` image
- Expected to handle Agent mode in Continue.dev reliably

---

## Next Steps

- [ ] Set up per-developer virtual API keys via LiteLLM admin UI
- [ ] Evaluate Agent mode on production box with Gemma 4 26B or 31B
- [ ] Add retry logic to `pdf_pipeline.py` for JSON parse failures