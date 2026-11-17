#!/usr/bin/env zsh
# Tests the Herdr resume block in dotfiles/zsh/.zshrc with fake hc/omp/claude.
# Usage: zsh tests/herdr-resume-test.zsh
emulate -L zsh
root=${0:A:h:h}
tmp=$(mktemp -d); trap 'rm -rf $tmp' EXIT
export HOME=$tmp/home LOG=$tmp/log HC_TERMINAL_ID=w1:t1
mkdir -p $HOME/.local/state/{omp,claude}-herdr-resume $tmp/bin
print -r -- '#!/bin/sh
echo "{\"created_ms\": 111}"' > $tmp/bin/hc
for p in omp claude; do print -r -- "#!/bin/sh
echo $p \"\$@\" >> \$LOG" > $tmp/bin/$p; done
chmod +x $tmp/bin/*
path=($tmp/bin $path)

# Load only the Herdr resume functions (the full .zshrc is not safe to source).
eval "$(sed -n '/^# Herdr: each terminal/,/^\[\[ ( -n \$HC_TERMINAL_ID/p' $root/dotfiles/zsh/.zshrc | sed '$d')"

omp_crumb=$HOME/.local/state/omp-herdr-resume/$HC_TERMINAL_ID
cl_crumb=$HOME/.local/state/claude-herdr-resume/$HC_TERMINAL_ID
osess=$tmp/osess.jsonl; csess=$tmp/abc-123.jsonl; touch $osess $csess
fail=0
check() { # name expected
  : > $LOG; precmd_functions=(_herdr_omp_resume); _herdr_omp_resume
  local got="$(<$LOG)"
  if [[ $got == $2 ]]; then print "ok   $1"; else print "FAIL $1: got '$got' want '$2'"; fail=1; fi
  rm -f $omp_crumb $cl_crumb
}

printf '111\n%s\n' $osess > $omp_crumb
check "only omp" "omp --resume $osess"

printf '111\n%s\n' $csess > $cl_crumb
check "only claude" "claude --resume abc-123"

printf '111\n%s\n' $osess > $omp_crumb; touch -t 202601010000 $omp_crumb
printf '111\n%s\n' $csess > $cl_crumb; touch -t 202601020000 $cl_crumb
check "both, claude newer" "claude --resume abc-123"

printf '111\n%s\n' $csess > $cl_crumb; touch -t 202601010000 $cl_crumb
printf '111\n%s\n' $osess > $omp_crumb; touch -t 202601020000 $omp_crumb
check "both, omp newer" "omp --resume $osess"

printf '111\n%s\nquit\n' $osess > $omp_crumb; touch -t 202601020000 $omp_crumb
printf '111\n%s\n' $csess > $cl_crumb; touch -t 202601010000 $cl_crumb
check "omp quit, claude valid" "claude --resume abc-123"

printf '222\n%s\n' $osess > $omp_crumb
printf '222\n%s\n' $csess > $cl_crumb
check "created_ms mismatch" ""

printf '111\n%s\nquit\n' $csess > $cl_crumb
check "claude quit only" ""

exit $fail
