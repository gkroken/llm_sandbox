#!/bin/bash
set -e

MODELS=(
  "code:Qwen/Qwen2.5-Coder-7B-Instruct-AWQ:--quantization awq_marlin"
  "chat:Qwen/Qwen2.5-7B-Instruct-AWQ:--quantization awq_marlin"
  "vision:Qwen/Qwen2-VL-2B-Instruct:"
  "gemma4:google/gemma-4-E4B-it:"
)

if [ -z "$1" ]; then
  echo "Usage: $0 [code|chat|vision]"
  echo ""
  echo "Available models:"
  for m in "${MODELS[@]}"; do
    key="${m%%:*}"
    rest="${m#*:}"
    val="${rest%%:*}"
    echo "  $key  →  $val"
  done
  exit 1
fi

TARGET_MODEL=""
TARGET_QUANT=""
for m in "${MODELS[@]}"; do
  key="${m%%:*}"
  rest="${m#*:}"
  val="${rest%%:*}"
  quant="${rest#*:}"
  if [ "$key" = "$1" ]; then
    TARGET_MODEL="$val"
    TARGET_QUANT="$quant"
    break
  fi
done

if [ -z "$TARGET_MODEL" ]; then
  echo "Unknown model: $1"
  exit 1
fi

echo "→ Switching to: $TARGET_MODEL"
sed -i "s|^ACTIVE_MODEL=.*|ACTIVE_MODEL=$TARGET_MODEL|" .env
sed -i "s|^ACTIVE_QUANT=.*|ACTIVE_QUANT=$TARGET_QUANT|" .env

docker compose stop vllm
docker compose up -d vllm
echo "✓ vLLM restarting with $TARGET_MODEL"
echo "  Watch: docker compose logs -f vllm"
