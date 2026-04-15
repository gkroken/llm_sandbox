# 2026-04-13 — Continue.dev + PDF Pipeline

**Goal:** Get IDE copilot working and prove the PDF extraction pipeline concept.

## Continue.dev

### Installation
Install the **Continue** extension from the VS Code marketplace.  
Open config with `Ctrl+Shift+P` → "Continue: Open config.yaml"

### Issues Hit
- **Context window error:** `--max-model-len 4096` was too small for Continue's combined prompt (system prompt + open file + chat history). Fix: increase to 8192 — we have 17,344 KV cache tokens available
- **Empty prompt error (`prompt: ''`):** Continue was using the legacy `/v1/completions` endpoint. Fix: add `useLegacyCompletionsEndpoint: false` to config
- **Agent mode:** Model got stuck in tool-use loops — expected for 7B, skip for now

### Working Config
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

### Practical Workflow at 7B
- `Ctrl+L` — chat, ask questions about code, toggle "Active file" for context
- `Ctrl+I` — inline edit, select code first then describe the change
- Agent mode — skip, too unreliable at 7B

## Model Switching Fix

`switch-model.sh` had no awareness of quantization — switching to the vision model passed
`--quantization awq_marlin` which Qwen2-VL-2B doesn't support (it's not an AWQ model).

Fix: encode the quantization flag per-model inside the script and inject via `ACTIVE_QUANT` in `.env`.
`docker-compose.yml` now has no hardcoded quantization — all model-specific config lives in the switch script.

## PDF Pipeline

### Setup
```bash
# Install uv (run once)
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env

# Switch to vision model
./switch-model.sh vision

# Run pipeline
cd ~/projects/llm-sandbox/tmp
uv run --with pymupdf --with openai python pdf_pipeline.py your_file.pdf
```

### How It Works
PyMuPDF renders each PDF page to PNG at 150 DPI → base64 encoded → sent to the vision model
with a JSON schema prompt → response parsed into structured JSON → saved as `filename_extracted.json`

### Test Results (scanned government letter, 8 pages)
- 7/8 pages extracted successfully
- Accurate extraction of dates, sender, recipient, addresses, phone numbers, key points
- 1 page failed with JSON parse error (model output malformed)
- Minor issues: occasional schema leakage (model returns schema text instead of null), occasional hallucinated extra fields
- All acceptable for PoC

### Known Limitations at 2B
- JSON parse failures (~1 in 8 pages) — needs retry logic
- Schema leakage — model sometimes copies schema text instead of returning null
- Hallucinated extra fields not in schema

### Production Expectations (Qwen2.5-VL-72B or similar)
- Near-perfect JSON compliance
- Handles tables, multi-column layouts, handwriting, degraded scans
- No model switching needed — all models run simultaneously

## What We Learned
- `context_window_fallback_dict` pointing to the same model is a no-op — the real fix is always `--max-model-len`
- `--break-system-packages` doesn't exist on Ubuntu 22.04's older pip — use `uv` instead
- Qwen2-VL-2B handles real scanned documents surprisingly well at this scale
- Quality gap between 2B and 72B on document tasks is qualitative, not just quantitative
- Full pipeline architecture proven: PDF → image → vision model → JSON works end to end