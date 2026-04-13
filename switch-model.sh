#!/bin/bash
set -e

MODELS=(
  "code:Qwen/Qwen2.5-Coder-7B-Instruct-AWQ"
  "chat:Qwen/Qwen2.5-7B-Instruct-AWQ"
  "vision:Qwen/Qwen2-VL-2B-Instruct"
)

if [ -z "$1" ]; then
  echo "Usage: $0 [code|chat|vision]"
  echo ""
  echo "Available models:"
  for m in "${MODELS[@]}"; do
    echo "  ${m%%:*}  →  ${m##*:}"
  done
  exit 1
fi

TARGET_MODEL=""
for m in "${MODELS[@]}"; do
  if [ "${m%%:*}" = "$1" ]; then
    TARGET_MODEL="${m##*:}"
    break
  fi
done

if [ -z "$TARGET_MODEL" ]; then
  echo "Unknown model: $1"
  exit 1
fi

echo "→ Switching to: $TARGET_MODEL"
sed -i "s|^ACTIVE_MODEL=.*|ACTIVE_MODEL=$TARGET_MODEL|" .env
docker compose stop vllm
docker compose up -d vllm
echo "✓ vLLM restarting with $TARGET_MODEL"
echo "  Watch: docker compose logs -f vllm"
