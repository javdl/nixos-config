{
  config,
  pkgs,
  lib,
  ...
}:

# Agent dev box for "jay" — runs rondo (https://github.com/sandsower/rondo),
# an autonomous Claude Code agent that polls Linear and works issues in isolated
# git-worktree workspaces.
#
# Reuses the decommissioned github-runner-01 box (Hetzner CCX33, 8 vCPU / 30 GB,
# Tailscale 100.78.158.57). Rebuilt in place — the disk layout is label-based
# (hosts/hardware/agent-jay-01.nix), so the hostname change is safe.
#
# To add another machine for jay: copy this file to hosts/agent-jay-NN.nix,
# change networking.hostName + the auto-update flake target + the hardware
# import, add a flake.nix entry, and reuse users/agent-jay/.
#
# rondo setup is the agent's responsibility (deps + manual run model):
#   - runtime (elixir/erlang/node/claude-code/gh) via `mise install`
#   - `claude` /login once (OAuth, persists in ~/.claude/.credentials.json)
#   - export LINEAR_API_KEY, clone rondo, run ./start_rondo.sh
# See docs/agent-dev-box-setup.md.

{
  imports = [
    ./hardware/agent-jay-01.nix
    ../modules/agent-dev-box.nix
  ];

  # Hostname
  networking.hostName = "agent-jay-01";

  # Auto-update from this host's flake target (daily at 04:00, see the module)
  services.nixosAutoUpdate.flake = "github:javdl/nixos-config#agent-jay-01";

  # NOTE: repoUpdater is intentionally NOT enabled here. Its root-run service
  # creates ~/.config/ru before home-manager populates the user's XDG dir, which
  # leaves ~/.config root-owned and blocks home-manager from writing
  # ~/.config/git/config etc. rondo clones each issue's repo into its own
  # workspace, so the human-oriented repo sync isn't needed on an agent box.

  # This value determines the NixOS release first installed; do not change it.
  system.stateVersion = "25.05";
}
