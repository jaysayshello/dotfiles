#!/usr/bin/env bash
# Render all tmux sessions as styled pills, sorted by name (numeric-aware).
# Output is consumed by status-left via #(...), so #[...] style markers work.

tmux list-sessions -F '#{session_attached}|#{session_name}' 2>/dev/null \
  | sort -t'|' -k2 -V \
  | while IFS='|' read -r attached name; do
      if [ "${attached:-0}" -ge 1 ]; then
        printf '#[fg=#1e1e2e,bg=#a6e3a1,bold] %s #[fg=#a6e3a1,bg=default] ' "$name"
      else
        printf '#[fg=#cdd6f4,bg=#313244] %s #[fg=#313244,bg=default] ' "$name"
      fi
    done
