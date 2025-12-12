#!/bin/bash
# Arch Linux (Omarchy) Software Uninstallation Commands
# Reverses the omarchy-packages.sh installation

set -e

echo "Uninstalling Arch packages installed by omarchy-packages.sh..."
echo ""

# Function to safely remove packages (ignores if not installed)
safe_remove() {
  echo "Removing: $@"
  yay -Rns --noconfirm $@ 2>/dev/null || true
}

# Audio Production & Music
echo "==> Removing Audio Production & Music..."
safe_remove reaper mixxx native-access ilok-license-manager

# Audio Plugins
echo "==> Removing Audio Plugins..."
safe_remove fabfilter softube-central izotope-product-portal spitfire-audio waves-central

# Miscellaneous Tools
echo "==> Removing Miscellaneous Tools..."
safe_remove neofetch fastfetch asciinema chezmoi peek rpi-imager balena-etcher

# Video & Streaming Utilities
echo "==> Removing Video & Streaming Utilities..."
safe_remove v4l2loopback-dkms v4l2loopback-utils

# Fonts
echo "==> Removing Fonts..."
safe_remove ttf-fira-code ttf-jetbrains-mono ttf-ibm-plex nerd-fonts-cascadia-code ttf-noto-nerd ttf-liberation ttf-font-awesome noto-fonts-cjk noto-fonts-emoji

# Backup & File Transfer
echo "==> Removing Backup & File Transfer..."
safe_remove transmission-qt vorta

# Database Tools
echo "==> Removing Database Tools..."
safe_remove postgresql mongodb-tools

# Security & Privacy
echo "==> Removing Security & Privacy..."
safe_remove bitwarden bitwarden-cli gnupg yubikey-manager veracrypt git-crypt

# System Utilities
echo "==> Removing System Utilities..."
safe_remove baobab gnome-disk-utility htop nethogs net-tools rsync p7zip unzip

# Cloud Storage & Sync
echo "==> Removing Cloud Storage & Sync..."
safe_remove nextcloud-client dropbox

# Productivity & Office
echo "==> Removing Productivity & Office..."
safe_remove calibre pandoc zathura zathura-pdf-poppler

# Browsers
echo "==> Removing Browsers..."
safe_remove firefox-developer-edition google-chrome brave-bin

# Communication & Social
echo "==> Removing Communication & Social..."
safe_remove discord slack-desktop signal-desktop thunderbird

# Graphics & Media Production
echo "==> Removing Graphics & Media Production..."
safe_remove gimp inkscape darktable digikam imagemagick ffmpeg vlc obs-studio libmpeg2 x264 gst-libav gst-plugins-ugly gst-plugins-bad

# AI & LLM Tools
echo "==> Removing AI & LLM Tools..."
safe_remove ollama aichat whisper aider-chat claude-code gemini-cli-git opencode-bin shell-gpt tgpt-git fabric-ai mods-bin lmstudio open-webui

# Programming Languages & Runtimes
echo "==> Removing Programming Languages & Runtimes..."
safe_remove rustup cargo-generate wasm-pack go python python-poetry python-uv nodejs npm

# Container & Cloud Tools
echo "==> Removing Container & Cloud Tools..."
safe_remove docker docker-compose podman podman-desktop k9s google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin google-cloud-cli-bq gcsfuse kubectl minikube skaffold flyctl

# Terminal & Shell Utilities
echo "==> Removing Terminal & Shell Utilities..."
safe_remove alacritty kitty tmux zellij fish starship atuin nushell bat eza fd tree watch jq httpie xh

# Development Tools & Editors
echo "==> Removing Development Tools & Editors..."
safe_remove jujutsu git-lfs github-cli glab visual-studio-code-bin cursor-bin sublime-text-4 zed helix jetbrains-toolbox air helix-gpt-bin ampcode-bin openai-codex-bin

echo ""
echo "==> Cleaning up orphaned packages..."
yay -Rns --noconfirm $(yay -Qdtq) 2>/dev/null || echo "No orphaned packages to remove"

echo ""
echo "==> Optionally restore removed Omarchy defaults? (basecamp, hey)"
read -p "Restore Omarchy defaults? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Restoring basecamp and hey..."
  yay -S --needed basecamp hey || true
fi

echo ""
echo "Done! All packages from omarchy-packages.sh have been removed."
echo ""
echo "Note: Some configuration files may remain in ~/.config and ~/.local"
echo "Run 'yay -Sc' to clear package cache if desired."
