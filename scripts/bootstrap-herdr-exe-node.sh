#!/usr/bin/env bash
set -euo pipefail

readonly herdr_version="0.8.2"
readonly herdr_sha256="976150a14d490c94b243ea2e1a7eb2dfb67f12e36b182db90936f6728e6aecf4"
readonly herdr_url="https://github.com/herdrdev/herdr/releases/download/v${herdr_version}/herdr-linux-x86_64"
readonly install_dir="${HOME}/.local/bin"
readonly config_dir="${HOME}/.config/herdr"
readonly unit_dir="${HOME}/.config/systemd/user"
runtime_dir="/run/user/$(id -u)"
readonly runtime_dir

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo "bootstrap-herdr-exe-node supports Linux x86_64 only" >&2
  exit 1
fi

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

"$install_dir/herdr" integration install claude
"$install_dir/herdr" integration install codex

sudo loginctl enable-linger "$(id -un)"
export XDG_RUNTIME_DIR="$runtime_dir"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus"
systemctl --user daemon-reload
systemctl --user enable --now herdr-agents.service

"$install_dir/herdr" --version
HERDR_SESSION=agents "$install_dir/herdr" status server --json
HERDR_SESSION=agents "$install_dir/herdr" workspace list
