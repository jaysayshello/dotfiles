#!/usr/bin/env zsh
# Tests that each prompt turns off the terminal modes a killed program can leave on.
# Usage: zsh tests/reset-modes-test.zsh
emulate -L zsh
root=${0:A:h:h}
precmd_functions=()

# Load only this block (the full .zshrc is not safe to source).
eval "$(sed -n '/^# A program that is killed (SIGKILL)/,/^precmd_functions+=(_reset_tui_modes)$/p' $root/dotfiles/zsh/.zshrc)"

fail=0
check() { # name condition
  if eval "$2"; then print "ok   $1"; else print "FAIL $1"; fail=1; fi
}
check "runs before each prompt" '(( ${precmd_functions[(I)_reset_tui_modes]} ))'
out=$(_reset_tui_modes 2>/dev/null)
for mode in '?2048l' '?1000l' '?1002l' '?1003l' '?1006l' '?1004l' '?2026l' '<u'; do
  check "turns off $mode" '[[ $out == *$'"'"'\e['"'"'"$mode"* ]]'
done
check "keeps bracketed paste (zsh uses it)" '[[ $out != *"?2004"* ]]'
exit $fail
