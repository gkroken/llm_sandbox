# Local LLM Sandbox

**Hardware:** Windows 10 Pro (22H2) + WSL2 Ubuntu 22.04 + RTX 3070 Ti 8GB  
**Goal:** PoC a fully local, private LLM stack that mirrors what we'd run on a production box (DGX Spark etc.)

See `notes/` for session logs and research notes.

---

## Architecture

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

## Prerequisites

### Windows side
- NVIDIA Game Ready or Studio driver (591.44 or later)
- WSL2 with Ubuntu 22.04
- **Do NOT install CUDA separately on Windows** — WSL2 handles it

### WSL2 Ubuntu side
- systemd enabled (`/etc/wsl.conf` → `[boot] systemd=true`)
- Docker Engine installed natively (not Docker Desktop)
- nvidia-container-toolkit installed and configured
- uv installed (`curl -LsSf https://astral.sh/uv/install.sh | sh`)

See `notes/sessions/2026-04-12-initial-setup.md` for the full first-time setup walkthrough.

---

## Day-to-Day Commands

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

# Test API
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-local-master-1234" \
  -d '{"model": "code-assistant", "messages": [{"role": "user", "content": "Hello"}]}'

# Run PDF pipeline (switch to vision model first)
./switch-model.sh vision
cd ~/projects/llm-sandbox/tmp
uv run --with pymupdf --with openai python pdf_pipeline.py your_file.pdf
```

---

## Access Points

| Service | URL | Notes |
|---|---|---|
| Open WebUI | http://localhost:3000 | Chat interface — connect to http://localhost:4000/v1 |
| LiteLLM API | http://localhost:4000 | OpenAI-compatible, key: `sk-local-master-1234` |
| LiteLLM Admin | http://localhost:4000/ui | Usage dashboard, virtual key management |
| vLLM direct | http://localhost:8001 | Internal only |

---

## Models

| Alias | Model | VRAM | Quantization | Use |
|---|---|---|---|---|
| code-assistant | Qwen/Qwen2.5-Coder-7B-Instruct-AWQ | ~5.5GB | awq_marlin | Copilot + chat |
| chat | Qwen/Qwen2.5-7B-Instruct-AWQ | ~5.5GB | awq_marlin | General chat |
| pdf-vision | Qwen/Qwen2-VL-2B-Instruct | ~3.5GB | none (FP16) | Document extraction |

Only one model runs at a time on 8GB VRAM. On the production box all run simultaneously.

The `switch-model.sh` script handles quantization flags automatically per model. Never hardcode `--quantization` in `docker-compose.yml`.

---

## Continue.dev Config (`~/.continue/config.yaml`)

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

| Feature | Shortcut | Status | Notes |
|---|---|---|---|
| Chat about code | `Ctrl+L` | ✅ | Toggle "Active file" for context |
| Inline edit | `Ctrl+I` | ✅ | Select code first |
| Autocomplete | automatic | ✅ | ~1-2s delay |
| Agent mode | sidebar | ⚠️ | Unreliable at 7B — needs production box with 32B+ |

---

## Known Issues

| Issue | Cause | Fix |
|---|---|---|
| `LITELLM_MASTER_KEY not set` warning | Env var not interpolated | Cosmetic — key is hardcoded in docker-compose.yml |
| `version obsolete` warning | Old compose format | Remove `version: "3.8"` line |
| Model not found 404 | Model name mismatch | Must be `openai/` + exact ID from `curl http://localhost:8001/v1/models` |
| Continue context window error | `--max-model-len` too small | Increase to 8192, restart vLLM |
| Continue empty prompt error | Legacy completions endpoint | Add `useLegacyCompletionsEndpoint: false` to continue config |
| Vision model fails with awq_marlin | Not an AWQ model | switch-model.sh handles this automatically |
| `uv not found` after install | PATH not updated | `source $HOME/.local/bin/env` |
| LiteLLM API refuses after startup | Prisma migrations still running | Wait ~30s after startup |
| vLLM healthcheck fails on large models | Load takes longer than start_period | Bump `start_period` to 300s, or run `docker compose up -d litellm open-webui` after vLLM is up |
| Gemma 4 fails with architecture error | vLLM image too old | Use `vllm/vllm-openai:gemma4` image, not `latest` |

---

## Production Migration Checklist

- [ ] Run multiple vLLM instances on different ports (one per model)
- [ ] Remove `--enforce-eager` and quantization flags
- [ ] Update `api_base` URLs in `litellm_config.yaml`
- [ ] Change `apiBase` in `~/.continue/config.yaml` to production box IP
- [ ] Use Qwen2.5-VL-72B for pdf-vision
- [ ] Set up per-developer virtual API keys via LiteLLM admin
- [ ] Evaluate Gemma 4 26B/31B for agent mode
- [ ] Evaluate OpenShell for agent governance
- [ ] Evaluate Daytona for code execution sandboxing
