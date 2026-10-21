#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a non-Nix Linux Herdr fleet worker (exe.dev VM, and the DGX
# Sparks until their user service is cut over). spark and spark2 also get
# herdr from Home Manager (homeConfigurations, lib/overlays.nix). This
# script's ~/.local/bin/herdr is still what the fleet remoteBin and the
# lingering user unit exec. Do not point those at the Nix profile until
# the unit is switched; see docs/dgx-spark.md.
# Version and hashes match the herdr release the Sparks were bootstrapped
# with. The overlay in lib/overlays.nix may be a newer release.
readonly herdr_version="0.9.3"
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    herdr_asset="herdr-linux-x86_64"
    herdr_sha256="18a8dc65f1c2fa485884344356dea1cfd911c6f06cf46fa78e193f4087f4dba7"
    ;;
  Linux-aarch64)
    herdr_asset="herdr-linux-aarch64"
    herdr_sha256="4de7aa3e25678812e92960de64f7c2aaa1bca1f0f80a3c5e559837e231e1f5c0"
    ;;
  *)
    echo "bootstrap-herdr-node supports Linux x86_64 and aarch64 only" >&2
    exit 1
    ;;
esac
readonly herdr_asset herdr_sha256
readonly herdr_url="https://github.com/herdrdev/herdr/releases/download/v${herdr_version}/${herdr_asset}"
readonly install_dir="${HOME}/.local/bin"
readonly config_dir="${HOME}/.config/herdr"
readonly unit_dir="${HOME}/.config/systemd/user"
runtime_dir="/run/user/$(id -u)"
readonly runtime_dir

for command in curl install loginctl sha256sum systemctl; do
  command -v "$command" >/dev/null || {
    echo "required command is missing: $command" >&2
    exit 1
  }
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -fsSL --retry 3 --connect-timeout 10 --max-time 120 \
  "$herdr_url" -o "$tmp_dir/herdr"
printf '%s  %s\n' "$herdr_sha256" "$tmp_dir/herdr" | sha256sum --check --status
install -Dm755 "$tmp_dir/herdr" "$install_dir/herdr"

cat >"$tmp_dir/config.toml" <<'EOF'
onboarding = false

[session]
resume_agents_on_restore = true

[remote]
manage_ssh_config = true
EOF
install -Dm644 "$tmp_dir/config.toml" "$config_dir/config.toml"

cat >"$tmp_dir/herdr-agents.service" <<EOF
[Unit]
Description=Persistent Herdr agents session
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=HERDR_SESSION=agents
Environment=PATH=${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=${install_dir}/herdr --session agents server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
install -Dm644 "$tmp_dir/herdr-agents.service" \
  "$unit_dir/herdr-agents.service"

# Same as the Nix fleet module: hooks install even before first login.
mkdir -p "$HOME/.claude" "$HOME/.codex"
"$install_dir/herdr" integration install claude
"$install_dir/herdr" integration install codex

if [[ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" != "yes" ]]; then
  sudo loginctl enable-linger "$(id -un)"
fi
export XDG_RUNTIME_DIR="$runtime_dir"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus"
systemctl --user daemon-reload
systemctl --user enable --now herdr-agents.service

"$install_dir/herdr" --version
HERDR_SESSION=agents "$install_dir/herdr" status server --json
HERDR_SESSION=agents "$install_dir/herdr" workspace list
