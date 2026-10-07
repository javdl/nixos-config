# Personal workstations only. Chezmoi owns mise/config.toml; this module owns
# scheduling and launchers. Omarchy retains ownership of /usr/bin/mise.
{ isOmarchy }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  mise = if isOmarchy then "/usr/bin/mise" else "${pkgs.mise}/bin/mise";
  updater = pkgs.writeShellScriptBin "agent-cli-update" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.git
        pkgs.curl
        pkgs.gnutar
        pkgs.gzip
        pkgs.unzip
      ]
    }:/usr/bin:/bin"
    exec ${pkgs.python3}/bin/python3 ${../../lib/agent-cli-update.py} ${mise}
  '';
  launcher =
    tool: fallback:
    pkgs.writeShellScriptBin tool ''
      binary="$HOME/.local/state/agent-cli-update/bin/${tool}"
      if [ -x "$binary" ]; then
        exec "$binary" "$@"
      fi
      exec ${fallback}/bin/${tool} "$@"
    '';
  launchers = {
    codex = launcher "codex" pkgs.codex;
    claude = launcher "claude" pkgs.claude-code;
  };
in
{
  # Override the profile's command names while retaining the pinned packages
  # as offline/bootstrap fallbacks. Do not change the shared server toolset.
  home.packages = [ updater ] ++ map lib.hiPrio (builtins.attrValues launchers);
  home.file = lib.mapAttrs' (
    tool: package: lib.nameValuePair ".local/bin/${tool}" { source = "${package}/bin/${tool}"; }
  ) (launchers // { agent-cli-update = updater; });

  home.activation.updateAgentClis = lib.hm.dag.entryAfter [ "writeBoundary" "chezmoiSync" ] ''
    # A locked Bitwarden vault can abort the full apply. Mise has no secrets.
    if [ -f "$HOME/.local/share/chezmoi/dot_config/mise/config.toml" ]; then
      $DRY_RUN_CMD ${pkgs.chezmoi}/bin/chezmoi apply "$HOME/.config/mise/config.toml" || \
        echo "mise config apply failed; updater will check the existing config" >&2
    fi
    $DRY_RUN_CMD ${lib.getExe updater} || \
      echo "Agent CLI update failed; retained previous launchers. See agent-cli-update logs or retry manually." >&2
  '';

  systemd.user.services.agent-cli-update = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Update and verify workstation Codex and Claude via mise";
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe updater;
      TimeoutStartSec = "20min";
    };
  };
  # Services do not source interactive shell activation. Give Moshi the same
  # profile launchers used by shells, ahead of the system's pinned binaries.
  systemd.user.services.moshi-hook = lib.mkIf pkgs.stdenv.isLinux {
    Service.Environment = [
      "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"
    ];
  };
  systemd.user.timers.agent-cli-update = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Check for agent CLI updates every six hours";
    Timer = {
      OnCalendar = "*-*-* 00,06,12,18:00:00";
      Persistent = true;
      RandomizedDelaySec = "15min";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  launchd.agents.agent-cli-update = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ (lib.getExe updater) ];
      RunAtLoad = true;
      StartInterval = 21600;
      ProcessType = "Background";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/agent-cli-update.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/agent-cli-update.log";
    };
  };
}
