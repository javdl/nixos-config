#!/usr/bin/env bash
# Bootstrap the Herdr command pane on an exe.dev VM (personal exe.dev account,
# default user exedev). Run on the VM:
#
#   ssh <vm>.exe.xyz 'bash -s' < scripts/bootstrap-herdr-cmdpane.sh
#
# Prerequisites (docs/herdr-command-center.md, "exe.dev command pane"):
#   - ~/.ssh/herdr-cmdpane on the VM: the private half of the `cmdpane` key in
#     users/herdr-fleet-keys.nix.
#   - An exe.dev Tailscale identity-federation integration attached to the VM
#     (default name tailscale-wif), backed by a personal-tailnet trust
#     credential that assigns tag:cmdpane.
#
# Idempotent: re-running skips finished steps and re-applies Home Manager.
set -euo pipefail

readonly wif_name="${EXE_WIF_NAME:-tailscale-wif}"
readonly flake="${HERDR_CMDPANE_FLAKE:-github:javdl/nixos-config#herdr-cmdpane}"
readonly key="${HOME}/.ssh/herdr-cmdpane"

if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
  echo "the command pane profile is x86_64-linux only" >&2
  exit 1
fi
if [[ ! -f "$key" ]]; then
  echo "missing $key: copy the command pane's private key first" >&2
  exit 1
fi
chmod 600 "$key"

for command in curl jq loginctl sudo systemctl; do
  command -v "$command" >/dev/null || {
    echo "required command is missing: $command" >&2
    exit 1
  }
done

# Tailscale: join the personal tailnet as tag:cmdpane without an auth key.
# Not ephemeral: an exe.dev VM that is briefly offline must keep its node.
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
# The installer does not always start the daemon (exe.dev images do not).
sudo systemctl enable --now tailscaled
for _ in $(seq 1 30); do
  tailscale status --json >/dev/null 2>&1 && break
  # NeedsLogin also exits non-zero; the socket existing is enough to proceed.
  [[ -S /run/tailscale/tailscaled.sock ]] && break
  sleep 1
done
if ! tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null; then
  wif_url="https://${wif_name}.int.exe.xyz"
  meta="$(curl -fsS "${wif_url}/metadata")"
  client_id="$(jq -er .client_id <<<"$meta")"
  id_token="$(curl -fsS "${wif_url}/token" | jq -er .token)"
  sudo tailscale up \
    --client-id="${client_id}?ephemeral=false&preauthorized=true" \
    --id-token="$id_token" \
    --advertise-tags=tag:cmdpane \
    --hostname=herdr-cmdpane
  unset id_token
fi
tailscale status --json | jq -e '.Self.Tags | index("tag:cmdpane")' >/dev/null || {
  echo "this node is not tagged tag:cmdpane; check the trust credential's tags" >&2
  exit 1
}

# Nix, via the Determinate installer (flakes enabled out of the box).
if ! command -v nix >/dev/null && [[ ! -x /nix/var/nix/profiles/default/bin/nix ]]; then
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
fi
# shellcheck disable=SC1091
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# The Herdr server and mirror are systemd user units; keep them running
# without a login session.
if [[ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" != "yes" ]]; then
  sudo loginctl enable-linger "$(id -un)"
fi
runtime_dir="/run/user/$(id -u)"
export XDG_RUNTIME_DIR="$runtime_dir"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus"

nix run home-manager/master -- switch -b pre-herdr --flake "$flake"

export PATH="${HOME}/.nix-profile/bin:${PATH}"
herdctl hosts
status=0
while read -r node _; do
  [[ "$node" == NODE ]] && continue
  if herdctl "$node" workspace list >/dev/null; then
    echo "ok      $node"
  else
    echo "FAILED  $node" >&2
    status=1
  fi
done < <(herdctl hosts)
exit "$status"
