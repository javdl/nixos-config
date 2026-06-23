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

  # Peter operates this agent box. He logs in as himself (peter@) and uses
  # `sudo -iu agent-jay` for agent ops (claude /login, rondo). Tailscale SSH also
  # needs "peter" in the tailnet ACL ssh-rule users; see docs/agent-dev-box-setup.md.
  users.users.peter = {
    isNormalUser = true;
    home = "/home/peter";
    extraGroups = [
      "docker"
      "wheel"
    ];
    shell = pkgs.zsh;
    hashedPassword = "!"; # SSH-key login only; passwordless sudo via wheel
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE3Ygpk7EQsrYKsE4wUAUdvuuRbWeDU5evzX5Cc07JtD peterpal@fu098"
    ];
  };

  # rondo's Linear API key, SOPS-encrypted (secrets/agent-jay-01.yaml), decrypted
  # at runtime via the box's SSH host key. Lands at /run/secrets/linear_api_key
  # owned by agent-jay; the rondo systemd service will read it (WORKFLOW.md uses
  # $LINEAR_API_KEY).
  sops.defaultSopsFile = ../secrets/agent-jay-01.yaml;
  sops.secrets.linear_api_key = {
    owner = "agent-jay";
    group = "users";
    mode = "0400";
  };

  # NOTE: repoUpdater is intentionally NOT enabled here. Its root-run service
  # creates ~/.config/ru before home-manager populates the user's XDG dir, which
  # leaves ~/.config root-owned and blocks home-manager from writing
  # ~/.config/git/config etc. rondo clones each issue's repo into its own
  # workspace, so the human-oriented repo sync isn't needed on an agent box.

  # This value determines the NixOS release first installed; do not change it.
  system.stateVersion = "25.05";
}
