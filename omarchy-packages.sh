#!/bin/bash
# Arch Linux (Omarchy) Software Installation Commands
# Based on NixOS configuration - excludes Omarchy defaults

set -e

echo "Installing Arch packages based on NixOS configuration..."
echo "Omarchy defaults excluded: neovim, ghostty, fzf, zoxide, ripgrep, lazygit, lazydocker, btop, chromium, spotify, obsidian, libreoffice"
echo ""

# Update system first to avoid version conflicts
echo "==> Updating system packages first..."
yay -Syu --noconfirm
echo ""

# Remove unwanted Omarchy defaults
echo "==> Removing unwanted Omarchy defaults..."
yay -Rns --noconfirm basecamp hey 2>/dev/null || true
echo ""

# Development Tools & Editors
echo "==> Installing Development Tools & Editors..."
yay -S --needed jujutsu git-lfs github-cli glab visual-studio-code-bin cursor-bin sublime-text-4 zed helix jetbrains-toolbox air helix-gpt-bin ampcode-bin openai-codex-bin

# Terminal & Shell Utilities
echo "==> Installing Terminal & Shell Utilities..."
yay -S --needed alacritty kitty tmux zellij fish starship atuin nushell bat eza fd tree watch jq httpie xh

# Container & Cloud Tools
echo "==> Installing Container & Cloud Tools..."
yay -S --needed docker docker-compose podman podman-desktop k9s google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin google-cloud-cli-bq gcsfuse kubectl minikube skaffold flyctl

# Programming Languages & Runtimes
echo "==> Installing Programming Languages & Runtimes..."
yay -S --needed rustup cargo-generate wasm-pack go python python-poetry python-uv nodejs npm

# AI & LLM Tools
echo "==> Installing AI & LLM Tools..."
yay -S --needed ollama aichat whisper aider-chat claude-code gemini-cli-git opencode-bin shell-gpt tgpt-git fabric-ai mods-bin lmstudio open-webui

# Graphics & Media Production
echo "==> Installing Graphics & Media Production..."
yay -S --needed gimp inkscape darktable digikam imagemagick ffmpeg vlc obs-studio libmpeg2 x264 gst-libav gst-plugins-ugly gst-plugins-bad

# Communication & Social
echo "==> Installing Communication & Social..."
yay -S --needed discord slack-desktop signal-desktop thunderbird

# Browsers
echo "==> Installing Browsers..."
yay -S --needed firefox-developer-edition google-chrome brave-bin

# Productivity & Office
echo "==> Installing Productivity & Office..."
yay -S --needed calibre pandoc zathura zathura-pdf-poppler

# Cloud Storage & Sync
echo "==> Installing Cloud Storage & Sync..."
yay -S --needed nextcloud-client dropbox

# System Utilities
echo "==> Installing System Utilities..."
yay -S --needed baobab gnome-disk-utility htop nethogs net-tools rsync p7zip unzip

# Security & Privacy
echo "==> Installing Security & Privacy..."
yay -S --needed bitwarden bitwarden-cli gnupg yubikey-manager veracrypt git-crypt

# Database Tools
echo "==> Installing Database Tools..."
yay -S --needed postgresql mongodb-tools

# Backup & File Transfer
echo "==> Installing Backup & File Transfer..."
yay -S --needed transmission-qt vorta

# Fonts
echo "==> Installing Fonts..."
yay -S --needed ttf-fira-code ttf-jetbrains-mono ttf-ibm-plex nerd-fonts-cascadia-code ttf-noto-nerd ttf-liberation ttf-font-awesome noto-fonts-cjk noto-fonts-emoji

# Video & Streaming Utilities
echo "==> Installing Video & Streaming Utilities..."
yay -S --needed v4l2loopback-dkms v4l2loopback-utils

# Miscellaneous Tools
echo "==> Installing Miscellaneous Tools..."
yay -S --needed neofetch fastfetch asciinema chezmoi peek rpi-imager balena-etcher

# Audio Production & Music
echo "==> Installing Audio Production & Music..."
yay -S --needed reaper mixxx native-access ilok-license-manager

echo ""
echo "==> Core packages installed!"
echo ""

# Audio Plugins (manual/vendor installation may be required)
echo "==> Installing Audio Plugins (some may require vendor installers)..."
yay -S --needed fabfilter softube-central izotope-product-portal spitfire-audio waves-central || echo "Some audio plugins may need manual installation from vendor websites"

echo ""
echo "=========================================="
echo "NOT AVAILABLE IN AUR:"
echo "=========================================="
echo "# devenv - use 'nix profile install nixpkgs#devenv' or install via Nix"
echo ""
echo "Done!"
