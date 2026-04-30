# macOS Configuration

My personal macOS development environment setup with window management, dotfiles, and automation scripts.

## Quick Start

```bash
git clone https://github.com/jaysayshello/dotfiles.git ~/Github/jaysayshello/dotfiles
cd ~/Github/jaysayshello/dotfiles
./install.sh
```

The install script will:
- Configure macOS defaults (`scripts/macos-defaults.sh`)
- Install Homebrew, dev tools, and applications
- Symlink Yabai, SKHD, Ghostty, Neovim, Opencode, llama-swap, tmux, and zsh configs into `~`
- Start Yabai and SKHD as services
- Install Oh My Zsh

Safe to re-run; it skips anything already installed.

## Directory Structure

```
config/
├── dotfiles/                   # Configuration files (organized by tool)
│   ├── cheatsheets/            # Personal reference notes (git, kubectl)
│   ├── ghostty/config
│   ├── llama-swap/config.yaml
│   ├── nvim/                   # LazyVim-based Neovim config
│   ├── opencode/               # Opencode TUI config + tokyonight-transparent theme
│   ├── skhd/                   # .skhdrc + .desktop_skhdrc + .laptop_skhdrc
│   ├── tmux/                   # .tmux.conf + sessions.sh (status-line renderer)
│   ├── yabai/                  # .yabairc + per-mode configs and centering scripts
│   └── zsh/.zshrc
├── scripts/
│   ├── desktop.sh              # Switch Yabai/SKHD to desktop mode (alias: `desktop`)
│   ├── laptop.sh               # Switch Yabai/SKHD to laptop mode (alias: `laptop`)
│   ├── work.sh                 # Open work apps (Slack, Reminders, Okta, Calendar)
│   ├── sync-dotfiles.sh        # Commit, pull --rebase, push
│   ├── macos-defaults.sh       # macOS system preferences
│   ├── local-llm-stack.sh      # Install/manage local LLM stack
│   └── start-llm-stack.sh      # Start the local LLM stack
└── install.sh                  # Main installation script
```

## Laptop vs Desktop Configurations

This setup supports separate Yabai/SKHD configurations for laptop and desktop.

### Switching Modes

- **Desktop Mode**: `desktop` — copies `.desktop_yabai` and `.desktop_skhdrc`, restarts services
- **Laptop Mode**: `laptop` — copies `.laptop_yabai` and `.laptop_skhdrc`, restarts services

### Window Centering

Different window sizes for each mode:
- **Laptop**: 1400x1000 (smaller for built-in displays)
- **Desktop**: 2000x1500 (larger for external monitors)

Trigger with `Shift+Cmd+E` to float/unfloat and center windows.

## Post-Installation Setup

### Yabai Accessibility Permissions

1. Open System Settings → Privacy & Security → Accessibility
2. Add `yabai` and `skhd` from `/opt/homebrew/bin`
   - They won't appear in the list, but they should still work after being added

### Run Initial Configuration

```bash
# For laptop setup
~/.laptop_yabai

# For desktop setup
~/.desktop_yabai
```

Or run `desktop` / `laptop` from the terminal to switch modes on the fly.

## Key Features

### Window Management (Yabai + SKHD)

- **Focus**: `Alt + h/j/k/l`
- **Swap**: `Shift + Alt + h/j/k/l`
- **Float/Center**: `Shift + Cmd + E`
- **Fullscreen**: `Alt + F`
- **Balance windows**: `Shift + Cmd + 2`
- **Rotate layout**: `Alt + R`
- **Create space**: `Cmd + Alt + N`
- **Move to space**: `Shift + Cmd + X/Z/C`

## Installed Applications

- **Terminal**: Ghostty
- **Development**: VSCode, Docker, Postman, DevUtils, Burp Suite
- **Fonts**: Fira Code, Fira Code Nerd Font
- **Security**: GPG Suite
- **Other**: Discord, KeepingYouAwake

(Chrome, Spotify, and Notion are commented out in `install.sh` — uncomment to install.)

## Customization

All configuration files live under `dotfiles/` and can be edited in place; the install script symlinks them into `~`, so changes take effect immediately.

After making structural changes (new files, new tool configs), re-run `./install.sh` to wire up any new symlinks.

## Notes

- Install script uses guarded installs, so it's safe to re-run
- GCP SDK paths are configured for `~/Desktop/google-cloud-sdk/`
- `sync-dotfiles.sh` is wired to a launchd job that periodically commits and pushes changes (logs to `scripts/sync-dotfiles.log`, gitignored)
