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
    # Use NixOS built-in Docker prune — only remove images/containers older than 24h
    # Keeps recently-pulled base images (node, etc.) so CI builds stay fast
    virtualisation.docker.autoPrune = {
      enable = true;
      dates = "daily";
      flags = [ "--all" "--filter" "until=24h" ];
    };

    # Prune build cache older than 7 days (keeps recent layer cache for faster builds)
    systemd.services.docker-builder-prune = {
      description = "Docker builder cache prune (>7d)";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      script = ''
        ${pkgs.docker}/bin/docker builder prune --force --filter "until=168h"
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
        OnCalendar = "weekly";
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
