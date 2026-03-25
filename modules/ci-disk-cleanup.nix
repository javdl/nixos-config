{ config, lib, pkgs, ... }:

# CI disk cleanup: Docker pruning, journal vacuum, tmp cleanup
# Designed for GitHub Actions runners where build artifacts are ephemeral

let
  cfg = config.services.ciDiskCleanup;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.ciDiskCleanup = {
    enable = mkEnableOption "CI disk cleanup (Docker, journal, tmp)";

    journalMaxSize = mkOption {
      type = types.str;
      default = "500M";
      description = "Maximum journal size to keep";
    };

    tmpCleanupAge = mkOption {
      type = types.str;
      default = "3d";
      description = "Delete tmp files older than this (systemd-tmpfiles age format)";
    };
  };

  config = mkIf cfg.enable {
    # Use NixOS built-in Docker prune (removes unused images, containers, networks)
    virtualisation.docker.autoPrune = {
      enable = true;
      dates = "daily";
      flags = [ "--all" "--volumes" ];
    };

    # Also prune build cache daily (not covered by docker system prune)
    systemd.services.docker-builder-prune = {
      description = "Docker builder cache prune";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      script = ''
        ${pkgs.docker}/bin/docker builder prune --all --force
      '';
      serviceConfig = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.docker-builder-prune = {
      description = "Timer for Docker builder cache prune";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = 900;
        Persistent = true;
      };
    };

    # Keep journal size bounded
    services.journald.extraConfig = ''
      SystemMaxUse=${cfg.journalMaxSize}
    '';

    # Clean old tmp files
    systemd.tmpfiles.rules = [
      "d /tmp 1777 root root ${cfg.tmpCleanupAge}"
    ];
  };
}
