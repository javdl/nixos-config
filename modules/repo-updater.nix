{ config, lib, pkgs, ... }:

# repo_updater (ru) module
#
# Installs the `ru` CLI and optionally runs a systemd timer to
# periodically sync repositories. Supports a Nix-managed repo list
# alongside user-managed imperative files.
#
# Ref: https://github.com/Dicklesworthstone/repo_updater

let
  cfg = config.services.repoUpdater;
  inherit (lib) mkEnableOption mkOption types mkIf;

  ru = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "repo-updater";
    version = "1.2.1";
    src = pkgs.fetchurl {
      url = "https://github.com/Dicklesworthstone/repo_updater/releases/download/v${version}/ru";
      sha256 = "sha256-fcRlzFpHECtoqYMgKxAm1FHXZ9dslp/gPG6sFya/Nwk=";
    };
    dontUnpack = true;
    installPhase = ''
      install -Dm755 $src $out/bin/ru
    '';
  };
in {
  options.services.repoUpdater = {
    enable = mkEnableOption "repo_updater (ru) periodic sync";

    package = mkOption {
      type = types.package;
      default = ru;
      description = "The repo_updater package to use";
    };

    user = mkOption {
      type = types.str;
      default = "joost";
      description = "User to run repo_updater as";
    };

    projectsDir = mkOption {
      type = types.str;
      default = "/home/${cfg.user}/code";
      description = "Directory where repositories are stored";
    };

    timerInterval = mkOption {
      type = types.str;
      default = "6h";
      description = "Systemd calendar interval for sync timer";
    };

    repos = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        List of GitHub repositories to sync (e.g. "owner/repo").
        Written to a Nix-managed config file that ru reads.
      '';
    };

    extraFlags = mkOption {
      type = types.listOf types.str;
      default = [ "--non-interactive" "--parallel" "4" ];
      description = "Extra flags passed to `ru sync`";
    };
  };

  config = mkIf cfg.enable {
    # Make ru available system-wide
    environment.systemPackages = [ cfg.package ];

    # Write Nix-managed repo list
    environment.etc."repo-updater/repos.txt" = mkIf (cfg.repos != []) {
      text = lib.concatStringsSep "\n" cfg.repos + "\n";
      mode = "0644";
    };

    # Ensure projects directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.projectsDir} 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.config/ru 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.config/ru/repos.d 0755 ${cfg.user} users -"
    ];

    # Symlink Nix-managed repos into ru's repos.d directory
    system.activationScripts.repoUpdaterLink = mkIf (cfg.repos != []) {
      text = ''
        mkdir -p /home/${cfg.user}/.config/ru/repos.d
        chown -R ${cfg.user}:users /home/${cfg.user}/.config/ru
        ln -sf /etc/repo-updater/repos.txt /home/${cfg.user}/.config/ru/repos.d/nix-managed.txt
        chown -h ${cfg.user}:users /home/${cfg.user}/.config/ru/repos.d/nix-managed.txt
      '';
    };

    # Systemd service for ru sync
    systemd.services.repo-updater-sync = {
      description = "Sync repositories with repo_updater";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git pkgs.gh pkgs.openssh pkgs.coreutils ];
      environment = {
        HOME = "/home/${cfg.user}";
        RU_PROJECTS_DIR = cfg.projectsDir;
      };
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = "users";
        ExecStart = "${cfg.package}/bin/ru sync ${lib.concatStringsSep " " cfg.extraFlags}";
        TimeoutStartSec = "30m";
      };
    };

    # Systemd timer
    systemd.timers.repo-updater-sync = {
      description = "Periodic repo_updater sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitInactiveSec = cfg.timerInterval;
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };
  };
}
