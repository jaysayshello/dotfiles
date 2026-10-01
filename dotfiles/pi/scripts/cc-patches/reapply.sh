#!/bin/bash
# better-claude-code-ui's status line is painted with theme dim/muted tokens,
# which read much darker than Claude Code's bar. This restores the ANSI-palette
# version (cyan cwd, magenta model, 37 separators, green/yellow/red context).
# node_modules is overwritten by `pi update --extensions`, so re-run this after.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
target="$HOME/.pi/agent/npm/node_modules/better-claude-code-ui/extension/status-line.ts"
[[ -f "$target" ]] || { echo "not installed: $target" >&2; exit 1; }
cp "$here/status-line.ts" "$target"
echo "restored CC status line colours -> $target"
