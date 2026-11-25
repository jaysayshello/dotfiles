#!/bin/bash
set -euo pipefail

rm -rf ~/.yabairc
rm -rf ~/.skhdrc
cp ~/.desktop_yabai ~/.yabairc
cp ~/.desktop_skhdrc ~/.skhdrc
yabai --restart-service || yabai --start-service
skhd --restart-service || skhd --start-service
bash "$(dirname "$0")/widgets.sh" desktop
