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
  config,
  pkgs,
  lib,
  ...
}:

let
  # omp and pi-agent evaluate to null on platforms upstream does not build for
  # (see lib/overlays.nix); the rest cover all four systems.
  optionalPkg = p: lib.optional (p != null) p;

  # Hook targets for both `herdr integration install <target>` and
  # `moshi-hook install --target`, which spell them identically. Kept in sync
  # with `herdr integration status` / `moshi-hook status`.
  hookTargets = [
    "claude"
    "codex"
    "opencode"
    "cursor"
    "grok"
  ]
  ++ lib.optional (pkgs.omp != null) "omp";

  # moshi-hook additionally covers gemini (gemini-cli ships from the per-user
  # profiles, not this module; the installer skips it while ~/.gemini is
  # absent). Left out on purpose: `pi` (same TypeScript-harness mismatch as
  # above) and `hermes`: on bali HERMES_HOME is the gateway's state dir, and
  # `moshi-hook install` there rewrote the gateway's config.yaml as joost-only
  # 0600, which cut the service off from its own settings.
  moshiTargets = hookTargets ++ [ "gemini" ];

  # Config directories each integration writes into. Herdr only creates the
  # extension/hook directory when the agent's own config dir already exists,
  # so make them first or the install is a silent no-op. (moshi-hook creates
  # them itself.)
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

    for target in ${lib.escapeShellArgs hookTargets}; do
      $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr integration install "$target" || \
        echo "herdr: integration $target unavailable, skipping" >&2
    done
  '';

  # Moshi agent hooks for every agent above. `moshi-hook install` embeds its
  # own store path in each hook command, so it re-runs on every switch to
  # track upgrades. It keeps foreign hooks in shared files, but always
  # re-serializes them.
  #
  # That rewrite matters for the settings files chezmoi owns on joost's
  # machines (dot_claude/settings.json.tmpl and dot_gemini/settings.json.tmpl
  # in javdl/dotfiles). Those templates carry the Moshi hooks and render this
  # same store path, so chezmoiSync (ordered first) already wrote them; a
  # reformatting second writer would drift the file from chezmoi's last write
  # and make the non-interactive `chezmoi apply` refuse to touch it. Such a
  # target is therefore skipped whenever its current hook command is already
  # present, which is also a harmless no-op for everyone else after the first
  # switch. If chezmoi could not apply (vault/drift/offline), the installer
  # fills the gap.
  #
  # Pairing (`moshi-hook pair --token …`) stays a manual, once-per-machine
  # step: the token comes from the phone.
  home.activation.moshiHookIntegrations =
    let
      moshiHook = "${pkgs.moshi-hook}/bin/moshi-hook";
      sharedSettings = {
        claude = ".claude/settings.json";
        gemini = ".gemini/settings.json";
      };
      addTarget =
        target:
        let
          add = ''targets="$targets''${targets:+,}${target}"'';
        in
        if sharedSettings ? ${target} then
          ''
            ${pkgs.gnugrep}/bin/grep -qF ${lib.escapeShellArg "'${moshiHook}' ${target}-hook"} \
              "$HOME/${sharedSettings.${target}}" 2>/dev/null || ${add}
          ''
        else
          add + "\n";
    in
    lib.hm.dag.entryAfter
      [
        "writeBoundary"
        "agentHerdrIntegrations"
        "chezmoiSync"
      ]
      ''
        targets=
        ${lib.concatMapStrings addTarget moshiTargets}
        if [ -n "$targets" ]; then
          $DRY_RUN_CMD ${moshiHook} install --target "$targets" || \
            echo "moshi-hook: hook install failed, skipping" >&2
        fi
      '';

  # moshi-hook daemon: systemd user service on Linux, launchd agent on Darwin.
  # Both mirror what `moshi-hook service install` would write, so do not also
  # run that by hand (two daemons would contend for the socket).
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

  # launchd hands agents a bare /usr/bin:/bin PATH; the daemon looks up
  # tmux/zellij/herdr to drive agent panes, so give it the Nix profiles.
  launchd.agents.moshi-hook = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.moshi-hook}/bin/moshi-hook"
        "serve"
      ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 10;
      ProcessType = "Background";
      EnvironmentVariables.PATH = lib.concatStringsSep ":" [
        "${config.home.profileDirectory}/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        "/opt/homebrew/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ];
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/moshi-hook.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/moshi-hook.log";
    };
  };
}
