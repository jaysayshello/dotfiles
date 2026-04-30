#!/bin/bash
set -euo pipefail

REPO="$HOME/Github/jaysayshello/config"
cd "$REPO"

git add .
if ! git diff --cached --quiet; then
    git -c commit.gpgsign=false commit -m "chore: sync dotfiles"
fi

stash_result=$(git stash)
git pull --rebase origin main
git push origin main
[[ "$stash_result" == "No local changes to save" ]] || git stash pop
