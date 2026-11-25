#!/bin/bash
set -euo pipefail

rm -rf ~/.yabairc
rm -rf ~/.skhdrc
cp ~/.laptop_yabai ~/.yabairc
cp ~/.laptop_skhdrc ~/.skhdrc
yabai --restart-service || yabai --start-service
skhd --restart-service || skhd --start-service
bash "$(dirname "$0")/widgets.sh" laptop
