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

  # rondo secrets, SOPS-encrypted (secrets/agent-jay-01.yaml), decrypted at runtime
  # via the box's SSH host key, owned by agent-jay:
  #   - linear_api_key: rondo's Linear tracker key (WORKFLOW.md uses $LINEAR_API_KEY)
  #   - github_token:   PAT for `gh` + the GitHub MCP, and for cloning fuww/api over
  #                     HTTPS in the workspace after_create hook.
  sops.defaultSopsFile = ../secrets/agent-jay-01.yaml;
  sops.secrets.linear_api_key = {
    owner = "agent-jay";
    group = "users";
    mode = "0400";
  };
  sops.secrets.github_token = {
    owner = "agent-jay";
    group = "users";
    mode = "0400";
  };

  # Render an EnvironmentFile (KEY=VALUE) for the rondo service from the secrets.
  # GH_TOKEN authenticates `gh`/git HTTPS; GITHUB_TOKEN is what the GitHub MCP reads.
  sops.templates."rondo.env" = {
    content = ''
      LINEAR_API_KEY=${config.sops.placeholder.linear_api_key}
      GH_TOKEN=${config.sops.placeholder.github_token}
      GITHUB_TOKEN=${config.sops.placeholder.github_token}
    '';
    owner = "agent-jay";
    group = "users";
    mode = "0400";
  };

  # rondo's WORKFLOW, declarative (mirrors Peter's working api profile). Lives in
  # /etc so it's not tangled with a git checkout; the service points here. It uses
  # $LINEAR_API_KEY (from the service env), so no secret is embedded.
  environment.etc."rondo/WORKFLOW.md" = {
    mode = "0444";
    text = ''
      ---
      tracker:
        kind: linear
        api_key: "$LINEAR_API_KEY"
        project_slug: "api-improvements-85cfc7553a54"
        label_filter:
          - AI-ready
        active_states:
          - Todo
          - In Progress
          - Merging
          - Rework
        terminal_states:
          - Closed
          - Cancelled
          - Canceled
          - Duplicate
          - Done
      polling:
        interval_ms: 60000
      workspace:
        root: ~/git/api-worktrees
      hooks:
        after_create: |
          git clone --depth 1 https://github.com/fuww/api .
          git submodule update --init
          mise trust && mise install
          # Activate mise for this non-interactive shell (rc files are not sourced here).
          if [ -n "$ZSH_VERSION" ]; then mise_shell=zsh; else mise_shell=bash; fi
          eval "$(mise activate "$mise_shell" --shims)"
          mise run setup
        before_remove: |
          docker compose down
      gates:
        - name: elixir-ci
          command: |
            if [ -n "$ZSH_VERSION" ]; then mise_shell=zsh; else mise_shell=bash; fi
            eval "$(mise activate "$mise_shell" --shims)" &&
            MIX_ENV=test mix ecto.migrate &&
            mix format --check-formatted &&
            mix credo &&
            mix espec
          timeout_ms: 1200000
      agent:
        adapter: claude_code
        max_concurrent_agents: 1
        max_turns: 20
      claude:
        command: claude
        permission_mode: bypassPermissions
        dangerously_skip_permissions: true
        max_turns: 50
        output_format: stream-json
      pi:
        command: pi
        turn_timeout_ms: 3600000
        stall_timeout_ms: 300000
      process_provider:
        kind: native
        required: false
      ---
    '';
  };

  # rondo as a managed service (runner-style): runs the prebuilt escript directly
  # on the nixpkgs beam (no mise), with LINEAR_API_KEY / GH tokens from SOPS and
  # the declarative /etc/rondo/WORKFLOW.md.
  #
  # ConditionPathExists keeps the unit dormant until bring-up is complete:
  #   - bin/rondo built, and
  #   - ~/.claude/.credentials.json present (a Claude login via caam — see docs).
  # The WORKFLOW is always present (declarative), so it's not a gate.
  # This avoids crash-looping before the agent is logged in.
  systemd.services.rondo = {
    description = "Rondo autonomous Claude Code agent (Linear tracker)";
    after = [
      "network-online.target"
      "sops-install-secrets.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = [
      "/home/agent-jay/git/rondo/elixir/bin/rondo"
      "/home/agent-jay/.claude/.credentials.json"
    ];
    serviceConfig = {
      User = "agent-jay";
      Group = "users";
      WorkingDirectory = "/home/agent-jay/git/rondo/elixir";
      EnvironmentFile = config.sops.templates."rondo.env".path;
      Environment = [
        "HOME=/home/agent-jay"
        # Runtime comes from the nixpkgs beam in agent-jay's profile (not mise).
        # ~/.local/bin: beislid policy stub + claude (native installer).
        "PATH=/home/agent-jay/.local/bin:/etc/profiles/per-user/agent-jay/bin:/run/current-system/sw/bin"
      ];
      ExecStart = "/home/agent-jay/git/rondo/elixir/bin/rondo --i-understand-that-this-will-be-running-without-the-usual-guardrails --port 5000 /etc/rondo/WORKFLOW.md";
      Restart = "on-failure";
      RestartSec = 15;
    };
  };

  # NOTE: repoUpdater is intentionally NOT enabled here. Its root-run service
  # creates ~/.config/ru before home-manager populates the user's XDG dir, which
  # leaves ~/.config root-owned and blocks home-manager from writing
  # ~/.config/git/config etc. rondo clones each issue's repo into its own
  # workspace, so the human-oriented repo sync isn't needed on an agent box.

  # This value determines the NixOS release first installed; do not change it.
  system.stateVersion = "25.05";
}
