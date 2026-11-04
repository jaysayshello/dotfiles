#!/bin/bash
# Fits the desktop widgets to the screen mode. laptop.sh and desktop.sh run it after yabai.
#   widgets.sh laptop   16" MacBook: compact Herdr alert; small Sanity at the top right, inside
#                       yabai's 150 px top padding (right edge on yabai's 64 px right padding)
#   widgets.sh desktop  big screen: large Herdr alert; Sanity at scale 1.75 at its desktop spot
# Sanity reads its size and place only when it starts, so this quits and starts it again.
set -euo pipefail

mode=${1:?usage: widgets.sh laptop|desktop}
sanity_id=com.jaysayshello.sanity
sanity_app=${SANITY_APP:-$HOME/Projects/macos-task-widgets-2026-08-03/build/Sanity.app}
tasks=$HOME/.config/sanity/tasks.md

case "$mode" in
  laptop)
    # 0.9: 128 pt high (116 * 0.9 + 24), 6 pt below the menu bar, 16 pt above the windows at
    # yabai's 150 pt top padding. Points, so the same on the MacBook and on a monitor.
    alert=compact scale=0.9
    # Sanity's width (contentSize() in its main.swift): open cards (done ones hidden), "+", toolbar.
    open_cards=$(grep -c '^## ' "$tasks" || true)
    done_cards=$(grep -c '^## \[x\]' "$tasks" || true)
    [ "$(defaults read "$sanity_id" hideDone 2>/dev/null || echo 0)" = 1 ] && open_cards=$((open_cards - done_cards))
    read -r win_x win_top < <(osascript -l JavaScript -e "
      ObjC.import('Cocoa');
      var v = \$.NSScreen.mainScreen.visibleFrame, s = $scale, n = $open_cards;
      var width = Math.max(2 * 14 * s + (n + 1) * 116 * s + 22 * s + 14 * s * (n + 1), 140);
      Math.round(v.origin.x + v.size.width - 64 - width) + ' ' + Math.round(v.origin.y + v.size.height - 6);")
    ;;
  desktop)
    # 2095 = the 2127 I placed it at, less the 32 pt title bar inset that Sanity no longer adds
    # (commit 5cffdd8): the cards stay where they were before that fix.
    alert=large scale=1.75 win_x=2237 win_top=2095
    ;;
  *) echo "usage: widgets.sh laptop|desktop" >&2; exit 1 ;;
esac

printf '%s\n' "$alert" > "$HOME/.config/herdr-app/alert-size"

osascript -e "tell application id \"$sanity_id\" to quit" >/dev/null 2>&1 || true
for _ in $(seq 1 20); do pgrep -qx Sanity || break; sleep 0.2; done
pkill -x Sanity 2>/dev/null || true
defaults write "$sanity_id" widgetScale -float "$scale"
defaults write "$sanity_id" winX -float "$win_x"
defaults write "$sanity_id" winTopY -float "$win_top"
open "$sanity_app"
echo "widgets: $mode (Herdr alert $alert, Sanity scale $scale at x=$win_x top=$win_top)"
