# Local LLM Sandbox — Setup & Operations Guide

Tested on: Windows 10 Pro (22H2) + WSL2 Ubuntu 22.04 + RTX 3070 Ti 8GB

---

## What This Is

A fully local, private LLM stack running on your own GPU. No cloud, no telemetry, no subscriptions. The architecture mirrors what you'd run on a production box (DGX Spark etc.) — just with smaller models due to 8GB VRAM.

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
- NVIDIA Game Ready or Studio driver installed (591.44 or later)
- WSL2 enabled with Ubuntu 22.04
- **Do NOT install CUDA separately on Windows** — WSL2 handles it

### WSL2 Ubuntu side
- systemd enabled (`/etc/wsl.conf` with `[boot] systemd=true`)
- Docker Engine installed natively (not Docker Desktop)
- nvidia-container-toolkit installed and configured

---

## First-Time Setup (Already Done)

These steps are complete — documented here for reference if rebuilding.

### 1. Enable systemd in WSL2
```bash
sudo tee /etc/wsl.conf > /dev/null <<EOF
[boot]
systemd=true
EOF
# Then in PowerShell: wsl --shutdown && wsl
```

### 2. Install Docker Engine
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

### 3. Install nvidia-container-toolkit
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

### 4. Verify GPU passthrough
```bash
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi
# Should show your RTX 3070 Ti
```

---

## Project Structure

```
~/projects/llm-sandbox/
├── docker-compose.yml      ← all services defined here
├── litellm_config.yaml     ← model routing config
├── .env                    ← HuggingFace token + active model
├── switch-model.sh         ← swap the active model
└── continue/
    └── config.yaml         ← copy to ~/.continue/config.yaml for VS Code
```

---

## Day-to-Day Usage

### Start the stack
```bash
cd ~/projects/llm-sandbox
docker compose up -d
```
First start after a reboot takes ~3-4 minutes for vLLM to load the model into VRAM. Subsequent starts are faster as the model is cached.

### Stop the stack
```bash
docker compose down
```
All data and model weights are preserved. Nothing is lost.

### Watch vLLM loading (if you want to monitor startup)
```bash
docker compose logs -f vllm
# Wait for: INFO Application startup complete.
```

### Check all services are healthy
```bash
docker compose ps
```
All three containers (vllm, litellm, open-webui) should show as `healthy` or `running`.

---

## Access Points

| Service | URL | Purpose |
|---|---|---|
| Open WebUI | http://localhost:3000 | Chat interface |
| LiteLLM API | http://localhost:4000 | OpenAI-compatible API |
| LiteLLM Admin | http://localhost:4000/ui | Usage dashboard |
| vLLM direct | http://localhost:8001 | Inference engine (internal) |

**API Key:** `sk-local-master-1234`

---

## Models

### Currently loaded
`Qwen/Qwen2.5-Coder-7B-Instruct-AWQ` — a 7B code + chat model, quantized to 4-bit AWQ format. Fits in ~5.2GB VRAM leaving room for KV cache.

### LiteLLM aliases (what you use in API calls)
- `code-assistant` — for copilot / code completion
- `chat` — for general chat
- `pdf-vision` — for document processing pipelines

All three currently route to the same model. On the production box they'd route to separate specialized models.

### Switching models (8GB VRAM = one model at a time)
```bash
./switch-model.sh code     # Qwen2.5-Coder-7B-AWQ
./switch-model.sh chat     # Qwen2.5-7B-AWQ
./switch-model.sh vision   # Qwen2-VL-2B (multimodal)
```
This restarts vLLM with a different model — takes 2-3 minutes.

### Available models for 8GB VRAM

| Alias | Model | VRAM | Use |
|---|---|---|---|
| code | Qwen/Qwen2.5-Coder-7B-Instruct-AWQ | ~5.5GB | Code copilot |
| chat | Qwen/Qwen2.5-7B-Instruct-AWQ | ~5.5GB | General chat |
| vision | Qwen/Qwen2-VL-2B-Instruct | ~3.5GB | PDF/image processing |

---

## API Usage

### Test the stack is working
```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-local-master-1234" \
  -d '{
    "model": "code-assistant",
    "messages": [{"role": "user", "content": "Write a hello world in Python"}]
  }'
```

### From Python
```python
import openai

client = openai.OpenAI(
    base_url="http://localhost:4000/v1",
    api_key="sk-local-master-1234"
)

response = client.chat.completions.create(
    model="code-assistant",
    messages=[{"role": "user", "content": "Write a hello world in Python"}]
)
print(response.choices[0].message.content)
```

---

## Known Issues & Fixes

### VRAM constraint
Windows uses ~1.1GB of the 3070 Ti's 8GB VRAM for the display. Effective available VRAM is ~6.9GB. The vLLM config uses `--gpu-memory-utilization 0.85` and `--max-model-len 4096` to stay within limits. Do not increase utilization above 0.85.

### LITELLM_MASTER_KEY warning
Docker compose shows `LITELLM_MASTER_KEY variable is not set` on startup — this is a cosmetic warning. The key is hardcoded directly in `docker-compose.yml` and works correctly. Safe to ignore.

### `version` obsolete warning
`docker-compose.yml: the attribute version is obsolete` — also cosmetic. Remove the `version: "3.8"` line from `docker-compose.yml` to silence it.

### Model not found (404)
If LiteLLM returns model not found, check that the model name in `litellm_config.yaml` matches exactly what vLLM reports:
```bash
curl http://localhost:8001/v1/models
```
The model field in `litellm_config.yaml` must be `openai/` + the exact ID from that response.

---

## vLLM Startup Flags Explained

```yaml
--model ${ACTIVE_MODEL}           # model to load from HuggingFace cache
--dtype half                      # FP16 precision
--quantization awq_marlin         # AWQ quantization with Marlin kernel (faster than plain awq)
--gpu-memory-utilization 0.85     # use 85% of available VRAM
--max-model-len 4096              # max context window (limited by VRAM)
--max-num-seqs 4                  # max concurrent requests
--enforce-eager                   # disable CUDA graph compilation (saves ~0.38GB VRAM)
```

On the production box (DGX Spark, 128GB unified memory) you'd remove `--enforce-eager`, increase `--max-model-len` to 32768+, increase `--max-num-seqs`, and drop `--quantization awq_marlin` for full precision models.

---

## Migrating to Production Box

The entire stack is identical. Only three things change:

1. **Remove `--enforce-eager`** and `--quantization awq_marlin` from vLLM command (run full precision)
2. **Run multiple vLLM instances** on different ports (one per model)
3. **Update `api_base` URLs** in `litellm_config.yaml` to point at the production box IP

`litellm_config.yaml` example for production:
```yaml
- model_name: code-assistant
  litellm_params:
    model: openai/Qwen/Qwen2.5-Coder-32B-Instruct
    api_base: http://production-box-ip:8001/v1
    api_key: dummy

- model_name: pdf-vision
  litellm_params:
    model: openai/Qwen/Qwen2-VL-7B-Instruct
    api_base: http://production-box-ip:8002/v1
    api_key: dummy
```

Continue.dev config: change `apiBase` from `http://localhost:4000/v1` to `http://production-box-ip:4000/v1`.

---

## Next Steps (Not Yet Done)

- [ ] Set up Continue.dev in VS Code for copilot-style code completion
- [ ] Create a HuggingFace token in `.env` and test model switching
- [ ] Write and test the PDF pipeline script (ACOS → multimodal → JSON → DB)
- [ ] Generate developer virtual keys via LiteLLM admin UI
- [ ] Set up `.wslconfig` to tune WSL2 memory allocation