#!/bin/bash

set -e  # Exit on error

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Starting setup from $SCRIPT_DIR"
echo ""

install_formula() {
  if brew list --formula "$1" &>/dev/null; then
    echo "  ⏭️  $1 already installed, skipping"
  else
    brew install "$1"
  fi
}

install_cask() {
  if brew list --cask "$1" &>/dev/null; then
    echo "  ⏭️  $1 already installed, skipping"
  else
    brew install --cask "$1"
  fi
}

# Setup MacOS Defaults
echo "📝 Setting up macOS defaults..."
chmod +x "$SCRIPT_DIR/scripts/macos-defaults.sh"
"$SCRIPT_DIR/scripts/macos-defaults.sh"
echo "✅ macOS defaults configured successfully"
echo ""

# Install Homebrew
echo "🍺 Installing Homebrew..."
if command -v brew &>/dev/null; then
  echo "  ⏭️  Homebrew already installed, skipping"
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  brew update
fi
echo "✅ Homebrew ready"
echo ""

# Development Tools
echo "🔧 Installing development tools..."
install_formula git
install_formula gh
install_formula go
install_formula tmux
install_formula neovim
install_formula ripgrep
install_formula fd
install_formula dockutil
install_formula docker
install_formula terraform
install_formula awscli
echo "✅ Development tools installed successfully"
echo ""

# Clear Dock
echo "🧹 Clearing dock..."
dockutil --remove all
echo "✅ Dock cleared successfully"
echo ""

# Applications
echo "📦 Installing applications..."
install_cask keepingyouawake
install_cask ghostty
install_cask visual-studio-code
install_cask burp-suite
install_cask postman
install_cask font-fira-code
install_cask font-fira-code-nerd-font
install_cask gpg-suite
install_cask devutils
#install_cask google-chrome
install_cask discord
#install_cask spotify
#install_cask notion
echo "✅ Applications installed successfully"
echo ""

# Yabai & SKHD Setup
echo "🪟 Setting up Yabai and SKHD..."
ln -sf "$SCRIPT_DIR/dotfiles/yabai/.yabairc" ~/
ln -sf "$SCRIPT_DIR/dotfiles/yabai/.desktop_yabai" ~/
ln -sf "$SCRIPT_DIR/dotfiles/yabai/.laptop_yabai" ~/
ln -sf "$SCRIPT_DIR/dotfiles/yabai/.yabai_center.sh" ~/
ln -sf "$SCRIPT_DIR/dotfiles/yabai/.desktop_yabai_center.sh" ~/
ln -sf "$SCRIPT_DIR/dotfiles/yabai/.laptop_yabai_center.sh" ~/
ln -sf "$SCRIPT_DIR/dotfiles/skhd/.skhdrc" ~/
ln -sf "$SCRIPT_DIR/dotfiles/skhd/.desktop_skhdrc" ~/
ln -sf "$SCRIPT_DIR/dotfiles/skhd/.laptop_skhdrc" ~/
chmod +x ~/.laptop_yabai ~/.desktop_yabai ~/.yabai_center.sh ~/.desktop_yabai_center.sh ~/.laptop_yabai_center.sh
#brew install koekeishiya/formulae/yabai || true
#brew install koekeishiya/formulae/skhd || true
skhd --start-service
yabai --start-service
echo "✅ Yabai and SKHD installed and started successfully"
echo ""

# Ghostty Configuration
echo "👻 Configuring Ghostty..."
mkdir -p ~/Library/Application\ Support/com.mitchellh.ghostty
ln -sf "$SCRIPT_DIR/dotfiles/ghostty/config" ~/Library/Application\ Support/com.mitchellh.ghostty/config
echo "✅ Ghostty configured successfully"
echo ""

# Neovim Configuration
echo "📝 Configuring Neovim..."
mkdir -p ~/.config
if [ -e ~/.config/nvim ] && [ ! -L ~/.config/nvim ]; then
  echo "  ⚠️  ~/.config/nvim exists and is not a symlink — skipping (back it up and re-run to replace)"
else
  ln -sfn "$SCRIPT_DIR/dotfiles/nvim" ~/.config/nvim
fi
echo "✅ Neovim configured successfully"
echo ""

# Opencode Theme
echo "🎨 Configuring Opencode theme..."
mkdir -p ~/.config/opencode/themes
ln -sf "$SCRIPT_DIR/dotfiles/opencode/themes/tokyonight-transparent.json" ~/.config/opencode/themes/tokyonight-transparent.json
ln -sf "$SCRIPT_DIR/dotfiles/opencode/tui.json" ~/.config/opencode/tui.json
echo "✅ Opencode theme configured successfully"
echo ""

# llama-swap Configuration
echo "🔀 Configuring llama-swap..."
mkdir -p ~/.config/llama-swap
if [ ! -f "$SCRIPT_DIR/dotfiles/llama-swap/config.yaml" ]; then
  cp "$SCRIPT_DIR/dotfiles/llama-swap/config.yaml.example" "$SCRIPT_DIR/dotfiles/llama-swap/config.yaml"
  echo "  ℹ️  Seeded dotfiles/llama-swap/config.yaml from example — edit with real endpoints (file is gitignored)"
fi
ln -sf "$SCRIPT_DIR/dotfiles/llama-swap/config.yaml" ~/.config/llama-swap/config.yaml
echo "✅ llama-swap config linked (binary install handled by local-llm-stack.sh)"
echo ""

# Oh My Zsh
echo "🐚 Installing Oh My Zsh..."
install_formula zsh
if [ ! -d ~/.oh-my-zsh ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" "" --unattended
fi
ln -sf "$SCRIPT_DIR/dotfiles/zsh/.zshrc" ~/
echo "✅ Oh My Zsh and shell config installed successfully"
echo ""

# Private overlays — sourced by .zshrc if present, untracked by design
echo "🔐 Bootstrapping private overlays (~/.work, ~/.secrets)..."
if [ ! -f ~/.work ]; then
  cp "$SCRIPT_DIR/dotfiles/zsh/.work.example" ~/.work
  echo "  ℹ️  Seeded ~/.work from .work.example — edit with employer-specific env vars/functions"
else
  echo "  ⏭️  ~/.work already exists, skipping"
fi
if [ ! -f ~/.secrets ]; then
  touch ~/.secrets
  chmod 600 ~/.secrets
  echo "  ℹ️  Created empty ~/.secrets (mode 600) — add API tokens / keys here"
else
  echo "  ⏭️  ~/.secrets already exists, skipping"
fi
echo "✅ Private overlays ready"
echo ""

# Tmux Configuration
echo "📟 Configuring tmux..."
ln -sf "$SCRIPT_DIR/dotfiles/tmux/.tmux.conf" ~/
mkdir -p ~/.local/bin
ln -sf "$SCRIPT_DIR/dotfiles/tmux/tmux-code" ~/.local/bin/tmux-code
ln -sf "$SCRIPT_DIR/dotfiles/tmux/tmux-code-reset" ~/.local/bin/tmux-code-reset
echo "✅ Tmux configured successfully"
echo ""

# Create .hushlogin
echo "🤫 Creating .hushlogin to suppress login messages..."
touch ~/.hushlogin
echo "✅ .hushlogin created successfully"
echo ""

echo "🎉 Installation complete!"
echo ""
echo "📝 Next steps:"
echo "  1. Restart your terminal"
echo "  2. Run ~/.laptop_yabai or ~/.desktop_yabai depending on your setup"
echo "  3. Enjoy your new environment!"
