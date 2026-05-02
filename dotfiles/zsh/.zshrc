# ============================================================================
# Oh My Zsh Configuration
# ============================================================================

export ZSH=$HOME/.oh-my-zsh
ZSH_THEME=""
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

eval "$(starship init zsh)"

bindkey '^F' autosuggest-accept

# ============================================================================
# Environment Variables
# ============================================================================

# Go
export GOPATH=$HOME/local/go
export PATH=$PATH:$GOPATH/bin

# ============================================================================
# Shell Configuration
# ============================================================================

unsetopt PROMPT_SP

# Load all saved ssh keys from macOS keychain
/usr/bin/ssh-add --apple-load-keychain 2>/dev/null

# Use legacy fzf keybindings
export FZF_LEGACY_KEYBINDINGS=1

# jump (directory navigation) — install with `brew install jump`
command -v jump >/dev/null && eval "$(jump shell zsh)"

# ============================================================================
# Aliases - Shell Management
# ============================================================================

alias ae='zed ~/.zshrc'
alias save='source ~/.zshrc'

# ============================================================================
# Aliases - Security & Encryption
# ============================================================================

alias encrypt='gpg -c --cipher-algo AES256 --s2k-digest-algo SHA512'
alias sha256='shasum -a 256'

# ============================================================================
# Aliases - Utilities
# ============================================================================

function dump() {
  local month_folder="$HOME/local/Dump/$(date +'%B %Y')"
  mkdir -p "$month_folder"
  local skip=(".DS_Store" "google-cloud-sdk")
  local name s
  for item in "$HOME/Desktop"/*(N); do
    name="$(basename "$item")"
    for s in "${skip[@]}"; do [[ "$name" == "$s" ]] && continue 2; done
    mv "$item" "$month_folder/"
  done
  echo "Dumped Desktop to $month_folder"
}

alias cheat='zed $HOME/Github/jaysayshello/dotfiles/dotfiles/cheatsheets'
alias ip='curl icanhazip.com'
alias knownhosts='cd ~/.ssh'
alias wm='launchctl kickstart -k "gui/$(id -u)/com.koekeishiya.yabai"; launchctl kickstart -k "gui/$(id -u)/com.koekeishiya.skhd"'
alias desktop='bash $HOME/Github/jaysayshello/dotfiles/scripts/desktop.sh'
alias laptop='bash $HOME/Github/jaysayshello/dotfiles/scripts/laptop.sh'
alias proxy='export HTTP_PROXY=http://127.0.0.1:8080; export HTTPS_PROXY=http://127.0.0.1:8080;'
alias unproxy='unset HTTP_PROXY; unset HTTPS_PROXY'
alias claude='claude --permission-mode bypassPermissions'
export CLAUDE_CODE_NO_FLICKER=1
export LOCAL_ENDPOINT=http://localhost:11434/v1
alias openqwen='OPENAI_API_KEY=ollama OPENAI_BASE_URL=http://localhost:11434/v1 CLOUDFLARE_API_TOKEN= CLOUDFLARE_ACCOUNT_ID= opencode'
alias start_model='launchctl load ~/Library/LaunchAgents/com.llamaserver.plist'
alias stop_model='launchctl unload ~/Library/LaunchAgents/com.llamaserver.plist'

# Browser mode switching
alias working="defaultbrowser chrome"
alias vibe="defaultbrowser safari"

# ============================================================================
# Aliases - Git Shortcuts
# ============================================================================

alias append='git commit --amend --no-edit -a'
alias push='git push origin HEAD --force-with-lease'
alias tf='terraform fmt -recursive && terragrunt hcl fmt'
alias emptypush='git commit -m "retrigger checks" --allow-empty'
alias fix='git add . && git commit -m "fix" && git push origin HEAD'
alias rebase='git fetch --all && git rebase origin/main && git push --force-with-lease origin $(git branch --show-current)'

function dotfiles() {
    local repo="$HOME/Github/jaysayshello/dotfiles"
    cd "$repo" || return 1
    git add .
    if git diff --cached --quiet; then
        echo "dotfiles: nothing to commit"
    else
        git commit -m "chore: sync dotfiles"
    fi
    git pull --rebase origin main && git push origin main
}

function squash() {
    local msg="${1}"
    if [[ -z "$msg" ]]; then
        echo "Usage: squash <commit message>"
        return 1
    fi
    git fetch --all && \
    git rebase origin/main && \
    git reset --soft origin/main && \
    git commit -m "$msg" && \
    git push --force-with-lease origin $(git branch --show-current)
}

# Open a file (or current dir) on GitHub at main branch
function ghfile() {
  local remote
  remote=$(git remote get-url origin 2>/dev/null) || { echo "No git remote"; return 1; }
  [[ "$remote" == git@github.com:* ]] && remote="https://github.com/${remote#git@github.com:}"
  remote="${remote%.git}"
  [[ "$remote" != https://github.com/* ]] && { echo "Not a GitHub remote: $remote"; return 1; }

  local git_root target rel_path
  git_root=$(git rev-parse --show-toplevel)
  target=$(realpath "${1:-.}")
  rel_path="${target#$git_root}"
  rel_path="${rel_path#/}"

  if [[ -d "$target" ]]; then
    open "${remote}/tree/main/${rel_path}"
  else
    open "${remote}/blob/main/${rel_path}"
  fi
}

# ============================================================================
# Functions
# ============================================================================

# Jump to nvim's last-saved cwd (written by a DirChanged autocmd in init)
function cdnv() {
  local f=~/.nvim-cwd
  [[ -r $f ]] || { echo "no nvim cwd recorded yet" >&2; return 1; }
  cd "$(<"$f")"
}

# Manually record the current shell's cwd as nvim's cwd
function nvcd() {
  pwd > ~/.nvim-cwd
}

# Attach to existing tmux session or create new
function tmux() {
  if command tmux has-session 2>/dev/null; then
    command tmux attach-session
  else
    command tmux "$@"
  fi
}

# Open files in VS Code
function code {
    if [[ $# = 0 ]]; then
        open -a "Visual Studio Code"
    else
        local argPath="$1"
        [[ $1 = /* ]] && argPath="$1" || argPath="$PWD/${1#./}"
        open -a "Visual Studio Code" "$argPath"
    fi
}

# Quick git commit and push
function lazygit() {
    git add .
    git commit -a -m "$1"
    git push origin $(git rev-parse --abbrev-ref HEAD)
}

# Interactively pick a branch across repos, checkout, and open in Zed
# Extra repo roots can be provided via $WORK_REPO_ROOTS (colon-separated).
function branches() {
    local roots=("$HOME/Github/jaysayshello")
    if [[ -n "$WORK_REPO_ROOTS" ]]; then
        local extra=("${(@s.:.)WORK_REPO_ROOTS}")
        roots=("${extra[@]}" "${roots[@]}")
    fi
    local entries=() root repo d name org label branch dirs line is_current

    for root in "${roots[@]}"; do
        [[ ! -d "$root" ]] && continue

        dirs=()
        if git -C "$root" rev-parse --git-dir &>/dev/null; then
            dirs=("$root")
        else
            setopt local_options nullglob
            for d in "$root"/*/; do
                git -C "$d" rev-parse --git-dir &>/dev/null && dirs+=("$d")
            done
        fi

        for repo in "${dirs[@]}"; do
            name=$(basename "$repo")
            org=$(basename "$(dirname "$repo")")
            [[ "$org" == "$(basename $HOME)" ]] && label="$name" || label="$org/$name"

            while IFS= read -r line; do
                if [[ "$line" == \** ]]; then
                    branch="${line#\* }"
                    is_current=1
                else
                    branch="${line#  }"
                    is_current=0
                fi
                [[ "$branch" =~ ^(main|master|develop)$ ]] && continue

                local cur_marker=""
                [[ $is_current -eq 1 ]] && cur_marker=$'\033[32m*\033[0m '
                local display=$'\033[2m'"${label}"$'\033[0m  \033[33m⎇\033[0m  '"${cur_marker}${branch}"
                entries+=("${display}"$'\t'"${repo%/}"$'\t'"${branch}")
            done < <(git -C "$repo" branch 2>/dev/null)
        done
    done

    [[ ${#entries[@]} -eq 0 ]] && { echo "No feature branches found."; return 1; }

    local selected
    selected=$(printf '%s\n' "${entries[@]}" | \
        fzf --delimiter=$'\t' \
            --with-nth=1 \
            --prompt='  branch > ' \
            --height=50% \
            --reverse \
            --ansi \
            --header=$'Enter: checkout & open in Zed\n' \
            --preview='git -C {2} log --oneline --color=always -15 {3} 2>/dev/null' \
            --preview-window=right:55%:wrap
    )

    [[ -z "$selected" ]] && return 0

    local sel_repo sel_branch
    sel_repo=$(awk -F$'\t' '{print $2}' <<< "$selected")
    sel_branch=$(awk -F$'\t' '{print $3}' <<< "$selected")

    cd "$sel_repo" || return 1
    git checkout "$sel_branch"
    zed .
}

# Show open PRs via GitHub GraphQL
# Set $WORK_GITHUB_ORG to filter to a specific org.
function prs() {
    local org_filter=""
    [[ -n "$WORK_GITHUB_ORG" ]] && org_filter=" org:$WORK_GITHUB_ORG"
    gh api graphql -f query='
      query {
        search(query: "is:pr is:open author:@me'"$org_filter"'", type: ISSUE, first: 30) {
          nodes {
            ... on PullRequest {
              title
              url
              headRefName
              repository { nameWithOwner }
            }
          }
        }
      }
    ' --jq '
        "\n\u001b[1mOpen PRs (" + (.data.search.nodes|length|tostring) + ")\u001b[0m",
        "─────────────────────────────────────────────────",
        (
            .data.search.nodes[] |
            "\n  \u001b[2m\(.repository.nameWithOwner)\u001b[0m",
            "  \u001b[33m⎇ \(.headRefName)\u001b[0m",
            "  \u001b[1m\(.title)\u001b[0m",
            "  \u001b[36m\(.url)\u001b[0m"
        )
    '
    echo ""
}

# Output a PR in Slack-ready format: [repo] title: url
# Usage: slackpr                              (current branch's PR)
#        slackpr <github-pr-url>              (any PR by URL)
function slackpr() {
    local arg="$1"
    local repo result
    if [[ -n "$arg" ]]; then
        repo=$(echo "$arg" | sed -n 's|.*github\.com/[^/]*/\([^/]*\)/pull/.*|\1|p')
        if [[ -z "$repo" ]]; then
            echo "Could not parse repo from URL: $arg" >&2
            return 1
        fi
        result=$(gh pr view "$arg" --json title,url 2>/dev/null)
    else
        repo=$(basename $(git rev-parse --show-toplevel 2>/dev/null))
        if [[ -z "$repo" ]]; then
            echo "Not in a git repo" >&2
            return 1
        fi
        result=$(gh pr view --json title,url 2>/dev/null)
    fi
    if [[ -z "$result" ]]; then
        echo "No PR found" >&2
        return 1
    fi
    local title=$(echo "$result" | jq -r '.title')
    local url=$(echo "$result" | jq -r '.url')
    local formatted="[\`$repo\`] $title: $url"
    echo "$formatted" | pbcopy
    echo "$formatted"
    echo "\n(copied to clipboard)"
}

# Cheat sheets
alias gitcheat='zed $HOME/Github/jaysayshello/dotfiles/dotfiles/cheatsheets/git.md'
alias kubecheat='zed $HOME/Github/jaysayshello/dotfiles/dotfiles/cheatsheets/kubectl.md'

. "$HOME/.local/bin/env"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"

eval "$(mise activate zsh)"

function close() {
  osascript <<'EOF'
tell application "System Events"
  set appList to name of every application process whose background only is false
end tell
repeat with appName in appList
  if (appName as text) is not "Ghostty" then
    try
      tell application (appName as text) to quit
    end try
  end if
end repeat
EOF
}

[[ -f "$HOME/.secrets" ]] && source "$HOME/.secrets"
[[ -f "$HOME/.work" ]] && source "$HOME/.work"

status_model() {
  local local_services=(
    "llama-server:8080:localhost"
    "Open WebUI:3000:localhost"
    "SearXNG:8888:localhost"
    "llama-swap:9090:localhost"
  )
  # Populate $REMOTE_SERVICES_LINES (newline-separated "name:port:host") in ~/.work
  local remote_services=()
  [[ -n "$REMOTE_SERVICES_LINES" ]] && remote_services=("${(@f)REMOTE_SERVICES_LINES}")
  local GREEN=$'\033[32m' RED=$'\033[31m' BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
  local entry name rest port host model ram

  _status_model_human_bytes() {
    awk -v b="$1" 'BEGIN{
      if (b=="" || b+0==0) { print "—"; exit }
      split("B KB MB GB TB", u, " "); s=1
      while (b>=1024 && s<5) { b/=1024; s++ }
      printf (s>=4 ? "%.1f%s" : "%.0f%s"), b, u[s]
    }'
  }

  _status_model_local_ram() {
    local pid rss_kb
    pid=$(lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1)
    [[ -z "$pid" ]] && { echo "—"; return; }
    rss_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -z "$rss_kb" ]] && { echo "—"; return; }
    _status_model_human_bytes $((rss_kb * 1024))
  }

  _status_model_row() {
    entry="$1"
    name="${entry%%:*}"
    rest="${entry#*:}"
    port="${rest%%:*}"
    host="${rest##*:}"
    if nc -z -w 1 "$host" "$port" 2>/dev/null; then
      case "$name" in
        "llama-server") model=$(curl -s -m 2 "http://$host:$port/v1/models" | jq -r '.data[0].id // "—"' 2>/dev/null) ;;
        "Ollama")       model=$(curl -s -m 2 "http://$host:$port/api/ps"    | jq -r '[.models[].name]   | if length==0 then "—" else join(", ") end' 2>/dev/null) ;;
        "llama-swap")   model=$(curl -s -m 2 "http://$host:$port/running"   | jq -r '[.running[].id]    | if length==0 then "—" else join(", ") end' 2>/dev/null) ;;
        *)              model="—" ;;
      esac
      [[ -z "$model" ]] && model="?"

      if [[ "$name" == "Ollama" ]]; then
        local total_bytes
        total_bytes=$(curl -s -m 2 "http://$host:$port/api/ps" | jq -r '[.models[].size] | add // 0' 2>/dev/null)
        ram=$(_status_model_human_bytes "$total_bytes")
      elif [[ "$host" == "localhost" || "$host" == "127.0.0.1" ]]; then
        ram=$(_status_model_local_ram "$port")
      else
        ram="—"
      fi

      printf "  %-14s %-6s %-16s ${GREEN}● up${RESET}    %-8s %s\n" "$name" "$port" "$host" "$ram" "$model"
    else
      printf "  %-14s %-6s %-16s ${RED}● down${RESET}  %-8s %s\n" "$name" "$port" "$host" "—" "—"
    fi
  }

  printf "${BOLD}LOCAL${RESET}\n"
  printf "  ${DIM}%-14s %-6s %-16s %-7s %-8s %s${RESET}\n" "SERVICE" "PORT" "HOST" "STATUS" "RAM" "LOADED MODEL"
  for entry in "${local_services[@]}"; do _status_model_row "$entry"; done
  printf "\n${BOLD}REMOTE${RESET}\n"
  printf "  ${DIM}%-14s %-6s %-16s %-7s %-8s %s${RESET}\n" "SERVICE" "PORT" "HOST" "STATUS" "RAM" "LOADED MODEL"
  for entry in "${remote_services[@]}"; do _status_model_row "$entry"; done

  unfunction _status_model_row _status_model_local_ram _status_model_human_bytes
}
