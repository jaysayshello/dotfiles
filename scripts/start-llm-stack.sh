#!/bin/bash

# Starts (or restarts) the local LLM stack:
#   - llama-server on :8080 (Qwen3.6 35B A3B, 32k context, vision enabled, mlock + cache-reuse)
#   - SearXNG on :8888 (launchd, typically already running)
#   - Open WebUI on :3000, wired to llama-server + SearXNG
#   - llama-swap on :9090, routing between local llama-server and desktop Ollama
#
# Logs go to /tmp/llama-server.log, /tmp/open-webui.log, /tmp/llama-swap.log.
# If com.llamaserver.plist is loaded, the port-8080 check will skip the
# direct llama-server start and defer to launchd — that's intentional.

set -e

MODEL_PATH="${MODEL_PATH:-$HOME/models/Qwen3.6-35B-A3B/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf}"
MMPROJ_PATH="${MMPROJ_PATH:-$(dirname "$MODEL_PATH")/mmproj-F16.gguf}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
OWUI_PORT="${OWUI_PORT:-3000}"
LLAMASWAP_PORT="${LLAMASWAP_PORT:-9090}"
LLAMA_CTX="${LLAMA_CTX:-32768}"
LLAMA_NGL="${LLAMA_NGL:-99}"
SEARXNG_PLIST="${SEARXNG_PLIST:-$HOME/Library/LaunchAgents/local.searxng.plist}"
LLAMASWAP_BIN="${LLAMASWAP_BIN:-$HOME/local/go/bin/llama-swap}"
LLAMASWAP_CFG="${LLAMASWAP_CFG:-$HOME/.config/llama-swap/config.yaml}"

is_listening() {
  lsof -iTCP:"$1" -sTCP:LISTEN -Pn 2>/dev/null | grep -q LISTEN
}

echo "🚀 Starting local LLM stack"
echo ""

# SearXNG (launchd)
echo "🔎 SearXNG..."
if launchctl list | grep -q local.searxng; then
  echo "  ⏭️  local.searxng already loaded (auto-starts on login)"
elif [ -f "$SEARXNG_PLIST" ]; then
  launchctl load "$SEARXNG_PLIST"
  echo "  ✅ Loaded local.searxng"
else
  echo "  ❌ launchd plist not found at $SEARXNG_PLIST"
  echo "     Run local-llm-stack.sh first."
  exit 1
fi
echo ""

# llama-server
echo "🧠 llama-server..."
if is_listening "$LLAMA_PORT"; then
  echo "  ⏭️  Something already listening on :$LLAMA_PORT"
  echo "     (if it is not llama-server, stop that process first)"
else
  if [ ! -f "$MODEL_PATH" ]; then
    echo "  ❌ Model not found at $MODEL_PATH"
    echo "     Download it or export MODEL_PATH to the correct location."
    exit 1
  fi
  mmproj_args=()
  if [ -f "$MMPROJ_PATH" ]; then
    mmproj_args=(--mmproj "$MMPROJ_PATH")
  else
    echo "  ⚠️  mmproj not found at $MMPROJ_PATH (vision will be disabled)"
  fi
  nohup llama-server \
    -m "$MODEL_PATH" \
    "${mmproj_args[@]}" \
    --host 127.0.0.1 --port "$LLAMA_PORT" \
    -c "$LLAMA_CTX" -ngl "$LLAMA_NGL" --jinja \
    --mlock --cache-reuse 256 \
    > /tmp/llama-server.log 2>&1 &
  echo "  ✅ Started llama-server (PID $!) on :$LLAMA_PORT (ctx $LLAMA_CTX$([ -f "$MMPROJ_PATH" ] && echo ', vision on'), mlock, cache-reuse=256)"
  echo "     Logs: /tmp/llama-server.log"
fi
echo ""

# Open WebUI
echo "💬 Open WebUI..."
if is_listening "$OWUI_PORT"; then
  echo "  ⏭️  Something already listening on :$OWUI_PORT"
else
  OPENAI_API_BASE_URL="http://127.0.0.1:${LLAMA_PORT}/v1" \
    OPENAI_API_KEY="sk-local" \
    WEBUI_AUTH=False \
    nohup open-webui serve --port "$OWUI_PORT" > /tmp/open-webui.log 2>&1 &
  echo "  ✅ Started open-webui (PID $!) on :$OWUI_PORT"
  echo "     Logs: /tmp/open-webui.log"
fi
echo ""

# llama-swap
echo "🔀 llama-swap..."
if is_listening "$LLAMASWAP_PORT"; then
  echo "  ⏭️  Something already listening on :$LLAMASWAP_PORT"
elif [ ! -x "$LLAMASWAP_BIN" ]; then
  echo "  ⚠️  $LLAMASWAP_BIN not found; skipping. Run local-llm-stack.sh first."
elif [ ! -f "$LLAMASWAP_CFG" ]; then
  echo "  ⚠️  $LLAMASWAP_CFG not found; skipping."
else
  nohup "$LLAMASWAP_BIN" \
    -config "$LLAMASWAP_CFG" \
    -listen ":$LLAMASWAP_PORT" \
    > /tmp/llama-swap.log 2>&1 &
  echo "  ✅ Started llama-swap (PID $!) on :$LLAMASWAP_PORT"
  echo "     Logs: /tmp/llama-swap.log"
fi
echo ""

# Wait for Open WebUI to become healthy
echo "⏳ Waiting for Open WebUI to respond..."
deadline=$(( $(date +%s) + 120 ))
until curl -sI --max-time 2 "http://127.0.0.1:${OWUI_PORT}/" >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "  ⚠️  Open WebUI did not respond within 120s. Check /tmp/open-webui.log"
    break
  fi
  sleep 2
done
echo ""

echo "🎉 Stack is up."
echo ""
echo "  Browser chat:    http://localhost:${OWUI_PORT}"
echo "  Terminal agent:  opencode"
echo "  llama-server:    http://localhost:${LLAMA_PORT}"
echo "  llama-swap:      http://localhost:${LLAMASWAP_PORT}/v1"
echo "  SearXNG:         http://localhost:8888"
echo ""
