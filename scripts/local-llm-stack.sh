#!/bin/bash

# Installs and configures the local LLM stack described in the
# "Local LLM Stack for Mac" Notion doc:
#   - llama.cpp (llama-server) running Qwen3.6 35B A3B on :8080 (vision enabled, mlock + cache-reuse, launchd-managed)
#   - SearXNG (bare-metal Python venv + launchd) on :8888
#   - Open WebUI (uv) on :3000, wired to llama-server + SearXNG
#   - pi coding agent (npm) pointed at llama-server
#   - llama-swap (prebuilt v204) on :9090, routing between local llama-server
#     and the desktop Ollama via `peers` config
#
# Idempotent: safe to re-run. SearXNG auto-starts on login via launchd.
# llama-server, Open WebUI, and llama-swap are installed but not started
# (use start-llm-stack.sh for that).

set -e

MODEL_PATH="${MODEL_PATH:-$HOME/models/Qwen3.6-35B-A3B/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf}"
MODEL_DIR="$(dirname "$MODEL_PATH")"
MODEL_FILE="$(basename "$MODEL_PATH")"
MODEL_REPO="${MODEL_REPO:-unsloth/Qwen3.6-35B-A3B-GGUF}"
MMPROJ_FILE="${MMPROJ_FILE:-mmproj-F16.gguf}"
MMPROJ_PATH="$MODEL_DIR/$MMPROJ_FILE"

LLAMASWAP_VERSION="${LLAMASWAP_VERSION:-v204}"
LLAMASWAP_BIN="$HOME/local/go/bin/llama-swap"
LLAMASWAP_CFG_DIR="$HOME/.config/llama-swap"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SEARXNG_CONF_DIR="$HOME/local/searxng"
SEARXNG_SRC_DIR="$HOME/local/searxng-src"
SEARXNG_VENV="$SEARXNG_SRC_DIR/venv"
SEARXNG_PLIST="$HOME/Library/LaunchAgents/local.searxng.plist"
SEARXNG_PYTHON="${SEARXNG_PYTHON:-python3.12}"
SEARXNG_PORT=8888
LLAMA_PORT=8080
OWUI_PORT=3000

OWUI_DB="$HOME/.local/share/uv/tools/open-webui/lib/python3.11/site-packages/open_webui/data/webui.db"

require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "  ❌ Required command missing: $1"
    echo "     $2"
    exit 1
  fi
}

echo "🦙 Installing local LLM stack"
echo ""

# Prerequisites
echo "🔍 Checking prerequisites..."
require_cmd brew   "Install Homebrew first: https://brew.sh"
require_cmd uv     "Install uv: brew install uv"
require_cmd node   "Install node: brew install node (opencode dependency)"
require_cmd go     "Install Go: brew install go"
require_cmd jq     "Install jq: brew install jq"
require_cmd git    "Install git: brew install git"
require_cmd sqlite3 "sqlite3 ships with macOS"
require_cmd "$SEARXNG_PYTHON" "Install Python 3.12: brew install python@3.12 (or set SEARXNG_PYTHON to the python you have)"
echo "  ✅ All prereqs present"
echo ""

# llama.cpp (provides llama-server)
echo "🧠 Installing llama.cpp..."
if brew list --formula llama.cpp &>/dev/null; then
  echo "  ⏭️  llama.cpp already installed"
else
  brew install llama.cpp
fi
echo ""

# Model download
echo "📥 Checking Qwen3.6 35B A3B GGUF..."
if [ -f "$MODEL_PATH" ] && [ -f "$MMPROJ_PATH" ]; then
  echo "  ⏭️  Model + mmproj already present at $MODEL_DIR"
else
  [ -f "$MODEL_PATH" ]  || echo "  Missing weights:  $MODEL_PATH"
  [ -f "$MMPROJ_PATH" ] || echo "  Missing mmproj:   $MMPROJ_PATH (needed for vision)"
  echo "  Source: https://huggingface.co/$MODEL_REPO (~21 GB weights + ~1 GB mmproj)"
  read -r -p "  Download now? [y/N] " reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    mkdir -p "$MODEL_DIR"
    if ! command -v huggingface-cli &>/dev/null; then
      echo "  Installing huggingface-cli via uv..."
      uv tool install "huggingface_hub[cli]"
    fi
    [ -f "$MODEL_PATH" ]  || huggingface-cli download "$MODEL_REPO" "$MODEL_FILE"  --local-dir "$MODEL_DIR" --local-dir-use-symlinks False
    [ -f "$MMPROJ_PATH" ] || huggingface-cli download "$MODEL_REPO" "$MMPROJ_FILE" --local-dir "$MODEL_DIR" --local-dir-use-symlinks False
  else
    echo "  ⏭️  Skipping download. Place the GGUF + mmproj at $MODEL_DIR before launching."
  fi
fi
echo ""

# llama-server launchd agent
#
# Writes (or overwrites) ~/Library/LaunchAgents/com.llamaserver.plist so
# llama-server auto-starts on login, restarts on crash, and uses --mlock to
# pin the ~21 GiB of weights in physical RAM (macOS will not page them out
# under pressure). --cache-reuse 256 lets the KV cache match prefix chunks
# across client reconnects (opencode/pi/Open WebUI restarts), turning
# ~40 s cold prefill into ~200 ms checkpoint restore.
echo "⚙️  Writing llama-server launchd plist..."
LLAMASERVER_PLIST="$HOME/Library/LaunchAgents/com.llamaserver.plist"
LLAMASERVER_CTX="${LLAMASERVER_CTX:-32768}"
LLAMASERVER_NGL="${LLAMASERVER_NGL:-99}"
mkdir -p "$HOME/Library/Logs"
cat > "$LLAMASERVER_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.llamaserver</string>

    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/llama-server</string>
        <string>-m</string>
        <string>${MODEL_PATH}</string>
        <string>--mmproj</string>
        <string>${MMPROJ_PATH}</string>
        <string>--host</string>
        <string>127.0.0.1</string>
        <string>--port</string>
        <string>${LLAMA_PORT}</string>
        <string>-c</string>
        <string>${LLAMASERVER_CTX}</string>
        <string>-ngl</string>
        <string>${LLAMASERVER_NGL}</string>
        <string>--jinja</string>
        <string>--mlock</string>
        <string>--cache-reuse</string>
        <string>256</string>
    </array>

    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>

    <key>WorkingDirectory</key>
    <string>${HOME}</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/llama-server.out.log</string>

    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/llama-server.err.log</string>
</dict>
</plist>
PLIST
echo "  ✅ Wrote $LLAMASERVER_PLIST"

if launchctl list | grep -q com.llamaserver; then
  launchctl unload "$LLAMASERVER_PLIST" 2>/dev/null || true
fi
launchctl load "$LLAMASERVER_PLIST"
echo "  ✅ Loaded com.llamaserver (auto-starts on login; --mlock pins ~21 GiB, --cache-reuse 256 warms prefix cache)"
echo ""

# SearXNG (bare-metal)
echo "🔎 Setting up SearXNG (bare-metal)..."
mkdir -p "$SEARXNG_CONF_DIR"
if [ ! -f "$SEARXNG_CONF_DIR/settings.yml" ]; then
  cat > "$SEARXNG_CONF_DIR/settings.yml" <<'YAML'
use_default_settings: true

server:
  secret_key: "change-me-local-only-9f8a1c2d"
  limiter: false
  image_proxy: true
  bind_address: "127.0.0.1"
  port: 8888

ui:
  static_use_hash: true

search:
  safe_search: 0
  autocomplete: ""
  default_lang: "en"
  formats:
    - html
    - json
YAML
  echo "  ✅ Wrote $SEARXNG_CONF_DIR/settings.yml"
else
  echo "  ⏭️  $SEARXNG_CONF_DIR/settings.yml already exists"
fi

if [ ! -d "$SEARXNG_SRC_DIR/.git" ]; then
  echo "  📥 Cloning searxng source..."
  git clone https://github.com/searxng/searxng.git "$SEARXNG_SRC_DIR"
else
  echo "  ⏭️  Source already present at $SEARXNG_SRC_DIR"
fi

if [ ! -x "$SEARXNG_VENV/bin/python" ]; then
  echo "  🐍 Creating venv..."
  "$SEARXNG_PYTHON" -m venv "$SEARXNG_VENV"
fi

echo "  📦 Installing dependencies (public PyPI)..."
"$SEARXNG_VENV/bin/pip" install --quiet --index-url https://pypi.org/simple \
  --upgrade pip setuptools wheel
"$SEARXNG_VENV/bin/pip" install --quiet --index-url https://pypi.org/simple \
  -r "$SEARXNG_SRC_DIR/requirements.txt" \
  -r "$SEARXNG_SRC_DIR/requirements-server.txt"
"$SEARXNG_VENV/bin/pip" install --quiet --index-url https://pypi.org/simple \
  --no-build-isolation -e "$SEARXNG_SRC_DIR"

if [ ! -f "$SEARXNG_PLIST" ]; then
  echo "  ⚙️  Writing launchd plist..."
  cat > "$SEARXNG_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.searxng</string>
  <key>ProgramArguments</key>
  <array>
    <string>${SEARXNG_VENV}/bin/granian</string>
    <string>--interface</string>
    <string>wsgi</string>
    <string>searx.webapp:application</string>
    <string>--host</string>
    <string>127.0.0.1</string>
    <string>--port</string>
    <string>${SEARXNG_PORT}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${SEARXNG_SRC_DIR}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SEARXNG_SETTINGS_PATH</key>
    <string>${SEARXNG_CONF_DIR}/settings.yml</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/searxng.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/searxng.log</string>
</dict>
</plist>
PLIST
fi

if launchctl list | grep -q local.searxng; then
  echo "  ⏭️  local.searxng already loaded"
else
  launchctl load "$SEARXNG_PLIST"
  echo "  ✅ Loaded local.searxng (auto-starts on login)"
fi
echo ""

# Open WebUI
echo "💬 Installing Open WebUI..."
if uv tool list 2>/dev/null | grep -qx "open-webui.*"; then
  echo "  ⏭️  open-webui already installed via uv"
else
  uv tool install open-webui --python 3.11
fi
echo ""

# Seed Open WebUI DB with SearXNG config
echo "⚙️  Configuring Open WebUI web search..."
if [ ! -f "$OWUI_DB" ]; then
  echo "  First launch required to create the DB. Booting Open WebUI briefly..."
  WEBUI_AUTH=False nohup open-webui serve --port "$OWUI_PORT" > /tmp/owui-init.log 2>&1 &
  owui_pid=$!
  # wait for DB file to appear and be populated
  until [ -f "$OWUI_DB" ] && sqlite3 "$OWUI_DB" "SELECT data FROM config LIMIT 1;" 2>/dev/null | grep -q '"rag"'; do
    sleep 2
  done
  kill "$owui_pid" 2>/dev/null || true
  wait "$owui_pid" 2>/dev/null || true
  # give sqlite a moment to release
  sleep 2
fi

cfg_json=$(sqlite3 "$OWUI_DB" "SELECT data FROM config LIMIT 1;")
new_cfg=$(echo "$cfg_json" | jq \
  '.rag.web.search.enable = true
   | .rag.web.search.engine = "searxng"
   | .rag.web.search.searxng_query_url = "http://127.0.0.1:8888/search?q=<query>"
   | .rag.web.search.result_count = 5
   | .rag.web.search.concurrent_requests = 5')
tmp_cfg=$(mktemp)
echo "$new_cfg" > "$tmp_cfg"
sqlite3 "$OWUI_DB" "UPDATE config SET data = readfile('$tmp_cfg');"
rm -f "$tmp_cfg"
echo "  ✅ SearXNG wired into Open WebUI DB"
echo ""

# llama-swap: install prebuilt binary + link repo config
# NOTE: `go install ...@latest` pulls v0.1.5 which predates the `peers` feature.
# We need a newer release; GitHub ships prebuilt darwin_arm64 tarballs.
echo "🔀 Installing llama-swap ($LLAMASWAP_VERSION)..."
mkdir -p "$(dirname "$LLAMASWAP_BIN")"
installed_version=""
if [ -x "$LLAMASWAP_BIN" ]; then
  installed_version="$("$LLAMASWAP_BIN" -version 2>&1 | awk '/^version:/ {print "v"$2; exit}')"
fi
if [ "$installed_version" = "$LLAMASWAP_VERSION" ]; then
  echo "  ⏭️  llama-swap $installed_version already installed"
else
  require_cmd gh "Install GitHub CLI: brew install gh"
  tmp="$(mktemp -d)"
  num="${LLAMASWAP_VERSION#v}"
  gh release download "$LLAMASWAP_VERSION" -R mostlygeek/llama-swap \
    -p "llama-swap_${num}_darwin_arm64.tar.gz" -D "$tmp" --clobber
  tar -xzf "$tmp/llama-swap_${num}_darwin_arm64.tar.gz" -C "$tmp"
  install -m 0755 "$tmp/llama-swap" "$LLAMASWAP_BIN"
  rm -rf "$tmp"
  echo "  ✅ Installed $("$LLAMASWAP_BIN" -version 2>&1 | head -1)"
fi

# Link repo config into ~/.config/llama-swap/
mkdir -p "$LLAMASWAP_CFG_DIR"
ln -sf "$REPO_ROOT/dotfiles/llama-swap/config.yaml" "$LLAMASWAP_CFG_DIR/config.yaml"
echo "  ✅ Config linked: $LLAMASWAP_CFG_DIR/config.yaml -> $REPO_ROOT/dotfiles/llama-swap/config.yaml"
echo ""

# opencode terminal agent
echo "💻 Installing opencode..."
# Use the upstream anomalyco tap — homebrew-core's formula has shipped a broken
# build (NAPI startup crash) and lags upstream releases.
if brew list --formula opencode &>/dev/null; then
  echo "  ⏭️  opencode already installed via brew (verify it's from anomalyco/tap, not homebrew-core)"
else
  brew install anomalyco/tap/opencode
fi

# opencode provider + MCP config (wired through llama-swap on :9090)
OPENCODE_CFG_DIR="$HOME/.config/opencode"
OPENCODE_CFG="$OPENCODE_CFG_DIR/opencode.json"
mkdir -p "$OPENCODE_CFG_DIR"
if [ -f "$OPENCODE_CFG" ]; then
  echo "  ⏭️  $OPENCODE_CFG already exists; leaving as-is"
else
  cat > "$OPENCODE_CFG" <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "disabled_providers": ["cloudflare-ai-gateway", "cloudflare-workers-ai"],
  "provider": {
    "llama-swap": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llama-swap (router)",
      "options": { "baseURL": "http://127.0.0.1:${LLAMASWAP_PORT:-9090}/v1" },
      "models": {
        "qwen-mac:35b-a3b": {
          "name": "Qwen 3.6 35B A3B (local Mac)",
          "attachment": true,
          "reasoning": true,
          "interleaved": { "field": "reasoning_content" },
          "modalities": { "input": ["text", "image"], "output": ["text"] }
        },
        "gemma4-remote:26b": {
          "name": "Gemma 4 26B (remote)",
          "attachment": true,
          "reasoning": true,
          "modalities": { "input": ["text", "image"], "output": ["text"] }
        },
        "qwen3.6:35b-a3b": {
          "name": "Qwen 3.6 35B A3B (remote)",
          "attachment": true,
          "reasoning": true,
          "modalities": { "input": ["text", "image"], "output": ["text"] }
        },
        "gemma4-lan:26b": {
          "name": "Gemma 4 26B (local server)",
          "attachment": true,
          "reasoning": true,
          "modalities": { "input": ["text", "image"], "output": ["text"] }
        }
      }
    }
  },
  "model": "llama-swap/qwen-mac:35b-a3b",
  "permission": "allow",
  "mcp": {
    "fetch":      { "type": "local",  "command": ["uvx", "mcp-server-fetch"],          "enabled": true },
    "duckduckgo": { "type": "local",  "command": ["uvx", "duckduckgo-mcp-server"],     "enabled": true },
    "serena":     { "type": "local",  "command": ["uvx", "--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server", "--context", "ide-assistant", "--open-web-dashboard", "false"], "enabled": true },
    "excalidraw": { "type": "remote", "url": "https://mcp.excalidraw.com",             "enabled": true }
  }
}
JSON
  echo "  ✅ Wrote $OPENCODE_CFG (default model: llama-swap/qwen-mac:35b-a3b)"
fi
echo ""

echo "🎉 Install complete."
echo ""
echo "Next steps:"
echo "  1. Launch the stack:   $(dirname "$0")/start-llm-stack.sh"
echo "  2. Browser chat:       http://localhost:${OWUI_PORT}"
echo "  3. Terminal agent:     opencode"
echo "  4. Raw llama-server:   http://localhost:${LLAMA_PORT}"
echo ""
