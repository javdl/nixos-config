# Agent CLI toolset shared by every account on every machine.
#
# Wired in from lib/mksystem.nix via home-manager.sharedModules (so it reaches
# every user on every NixOS and Darwin host) and from the two standalone Home
# Manager configs in flake.nix, which have no system layer to inherit from.
#
# The set is deliberately the intersection of what Herdr and moshi-hook can
# drive: claude, codex, opencode, cursor, grok and omp. Herdr also offers a
# `pi` integration, but it targets Mario Zechner's TypeScript Pi harness
# (~/.pi/agent/extensions/*.ts), which is a different tool from the Rust
# pi-agent this repo packages. Installing it would drop an extension nothing
# loads, so pi ships as a binary here without a Herdr integration.
{
  pkgs,
  lib,
  ...
}:

let
  # omp and pi-agent evaluate to null on platforms upstream does not build for
  # (see lib/overlays.nix); the rest cover all four systems.
  optionalPkg = p: lib.optional (p != null) p;

  # Herdr integration targets, in `herdr integration install <target>` spelling.
  # Kept in sync with `herdr integration status`.
  herdrTargets = [
    "claude"
    "codex"
    "opencode"
    "cursor"
    "grok"
  ]
  ++ lib.optional (pkgs.omp != null) "omp";

  # Config directories each integration writes into. Herdr only creates the
  # extension/hook directory when the agent's own config dir already exists,
  # so make them first or the install is a silent no-op.
  agentConfigDirs = [
    ".claude"
    ".codex"
    ".config/opencode"
    ".cursor"
    ".grok"
    ".omp/agent"
  ];
in
{
  home.packages = [
    pkgs.claude-code
    pkgs.codex
    pkgs.cursor-cli
    pkgs.grok-build
    pkgs.opencode
    pkgs.herdr
    pkgs.moshi-hook
  ]
  ++ optionalPkg pkgs.omp
  ++ optionalPkg pkgs.pi-agent;

  # Publish agent lifecycle state to Herdr on every machine. Authentication for
  # each agent stays an explicit, machine-local interactive step; this only
  # writes the hook/plugin files. Failures are tolerated so one unavailable
  # agent cannot abort the whole home-manager activation.
  home.activation.agentHerdrIntegrations = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for dir in ${lib.escapeShellArgs agentConfigDirs}; do
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$HOME/$dir"
    done

    for target in ${lib.escapeShellArgs herdrTargets}; do
      $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr integration install "$target" || \
        echo "herdr: integration $target unavailable, skipping" >&2
    done
  '';

  # moshi-hook daemon for the Moshi mobile app. Linux only: Home Manager has no
  # systemd on Darwin, where `moshi-hook service install` writes a launchd agent
  # instead.
  #
  # Pairing is deliberately NOT automated. `moshi-hook pair` needs a token from
  # the phone, and `moshi-hook install` rewrites ~/.claude/settings.json, which
  # chezmoi already owns as a template (see CLAUDE.md) — a third writer there
  # would fight the chezmoi sync. Run both by hand once per machine.
  systemd.user.services.moshi-hook = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    Unit = {
      Description = "moshi-hook daemon (Moshi mobile app bridge)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.moshi-hook}/bin/moshi-hook serve";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
