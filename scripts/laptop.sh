#!/bin/bash
set -euo pipefail

rm -rf ~/.yabairc
rm -rf ~/.skhdrc
cp ~/.laptop_yabai ~/.yabairc
cp ~/.laptop_skhdrc ~/.skhdrc
launchctl kickstart -k "gui/$(id -u)/com.koekeishiya.yabai"
launchctl kickstart -k "gui/$(id -u)/com.koekeishiya.skhd"
