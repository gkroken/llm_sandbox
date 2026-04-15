# 2026-04-12 — Initial Setup

**Goal:** Get the full stack running from scratch on WSL2.

## System State Going In
- Windows 10 Pro, NVIDIA driver 591.44
- WSL2 Ubuntu 22.04 already initiated but barely configured
- Docker installed via Docker Desktop — wanted native Docker Engine in WSL2
- No CUDA toolkit in WSL (correct — WSL2 gets it from the Windows driver)

## First-Time Setup Steps

### 1. Enable systemd in WSL2
```bash
sudo tee /etc/wsl.conf > /dev/null <<EOF
[boot]
systemd=true
EOF
# Then in PowerShell: wsl --shutdown && wsl
# Verify: ps -p 1 -o comm=  → should print "systemd"
```

### 2. Install Docker Engine natively
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
# Should show RTX 3070 Ti
```

### 5. Install uv
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env
```

## What We Did
- Confirmed systemd was already running (`ps -p 1` → systemd)
- Removed stale Docker Desktop plugin stubs from `/usr/local/lib/docker/cli-plugins/`
- Fixed ownership of `~/projects` (owned by root) with `chown -R gakro:gakro`
- Created project structure and all config files
- Got HuggingFace Read token — Qwen models are not gated, no license agreement needed
- Brought up the stack — hit two vLLM crashes:
  - **Crash 1:** `gpu_memory_utilization 0.90` requested 7.2GB but only 6.92GB free — Windows display uses ~1.1GB. Fix: drop to 0.85
  - **Crash 2:** KV cache had no room after model loaded. Fix: add `--enforce-eager` and switch to `awq_marlin` quantization
- LiteLLM wouldn't auth — `LITELLM_MASTER_KEY` not interpolated from `.env` — hardcoded directly in `docker-compose.yml`
- Model name wrong format — needed `openai/Qwen/Qwen2.5-Coder-7B-Instruct-AWQ` (with `openai/` prefix)
- Added Postgres container for LiteLLM spend tracking (required for auth)
- First successful API response 🎉

## What We Learned
- Windows display eats ~1.1GB of VRAM — effective VRAM on 3070 Ti is ~6.9GB, not 8GB
- `--quantization awq_marlin` is faster than `--quantization awq` — vLLM recommends it in its own logs
- `--enforce-eager` disables CUDA graph compilation, saves ~0.38GB VRAM at ~10% speed cost
- Docker compose doesn't always interpolate `.env` — when in doubt, hardcode
- LiteLLM model name must be `openai/` + exact HuggingFace model ID — verify with `curl localhost:8001/v1/models`
- Open WebUI requires manual connection setup: Manage Connections → http://localhost:4000/v1