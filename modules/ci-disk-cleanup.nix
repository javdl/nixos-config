{ config, lib, pkgs, ... }:

# CI disk cleanup: Docker pruning, journal vacuum, tmp cleanup, tool cache cleanup
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

    diskThresholdGB = mkOption {
      type = types.int;
      default = 20;
      description = "Trigger emergency cleanup when free space drops below this (GB)";
    };

    runnerWorkDir = mkOption {
      type = types.str;
      default = "/run/github-runner";
      description = "GitHub Actions runner work directory root";
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

    # Proactive disk space monitor — runs every 10 minutes
    # Cleans Docker, Actions tool cache, and nix store when disk is low
    systemd.services.ci-disk-monitor = {
      description = "CI disk space monitor and emergency cleanup";
      after = [ "docker.service" ];
      path = with pkgs; [ coreutils gawk docker nix ];
      script = ''
        set -euo pipefail
        THRESHOLD=${toString cfg.diskThresholdGB}
        RUNNER_DIR="${cfg.runnerWorkDir}"

        AVAIL_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
        echo "Available: ''${AVAIL_GB}GB, threshold: ''${THRESHOLD}GB"

        if [ "$AVAIL_GB" -lt "$THRESHOLD" ]; then
          echo "=== LOW DISK SPACE — running emergency cleanup ==="

          # 1. Clean GitHub Actions tool cache (setup-gcloud, setup-node, etc.)
          #    These re-download on next use, so safe to remove
          if [ -d "$RUNNER_DIR" ]; then
            find "$RUNNER_DIR" -type d -name "_tool" -exec rm -rf {} + 2>/dev/null || true
            find "$RUNNER_DIR" -type d -name "_temp" -exec rm -rf {} + 2>/dev/null || true
            echo "Cleaned Actions tool/temp caches"
          fi

          # 2. Aggressive Docker cleanup — remove everything older than 4h
          docker system prune --all --force --filter "until=4h" 2>/dev/null || true
          docker builder prune --all --force 2>/dev/null || true
          echo "Cleaned Docker images and build cache"

          # 3. Nix store GC
          nix-collect-garbage --delete-older-than 3d 2>/dev/null || true
          echo "Ran nix garbage collection"

          # 4. Clean old logs
          journalctl --vacuum-size=200M 2>/dev/null || true

          NEW_AVAIL=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
          echo "Available after cleanup: ''${NEW_AVAIL}GB"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.ci-disk-monitor = {
      description = "Timer for CI disk space monitor";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = "10m";
        AccuracySec = "1m";
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
