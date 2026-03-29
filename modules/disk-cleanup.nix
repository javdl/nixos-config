{ config, lib, pkgs, ... }:

# Weekly disk cleanup for dev servers
#
# Cleans: audit logs, journal, tmp files, Docker/Podman, nix store generations
# Prevents the disk-full incidents caused by runaway auditd logging

let
  cfg = config.services.diskCleanup;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.diskCleanup = {
    enable = mkEnableOption "weekly disk cleanup (logs, tmp, containers, nix)";

    journalMaxSize = mkOption {
      type = types.str;
      default = "1G";
      description = "Maximum journal size to keep";
    };

    tmpCleanupAge = mkOption {
      type = types.str;
      default = "7d";
      description = "Delete tmp files older than this (systemd-tmpfiles age format)";
    };

    nixKeepDays = mkOption {
      type = types.int;
      default = 14;
      description = "Keep nix generations from the last N days";
    };
  };

  config = mkIf cfg.enable {
    # Weekly cleanup service
    systemd.services.disk-cleanup = {
      description = "Weekly disk cleanup (logs, tmp, containers, nix)";
      path = with pkgs; [ coreutils gawk findutils ];
      script = ''
        set -euo pipefail
        echo "=== Weekly disk cleanup starting ==="
        df -h / | tail -1

        # 1. Audit logs — delete rotated, truncate current
        if [ -d /var/log/audit ]; then
          find /var/log/audit -name 'audit.log.*' -delete 2>/dev/null || true
          truncate -s 0 /var/log/audit/audit.log 2>/dev/null || true
          echo "Cleaned audit logs"
        fi

        # 2. Journal vacuum
        journalctl --vacuum-size=${cfg.journalMaxSize} 2>/dev/null || true

        # 3. Stale tmp dirs (worktrees, scans, build artifacts)
        find /tmp -mindepth 1 -maxdepth 1 -mtime +7 -exec rm -rf {} + 2>/dev/null || true
        echo "Cleaned old tmp files"

        # 4. Docker prune (if running)
        if command -v docker &>/dev/null && systemctl is-active docker &>/dev/null; then
          docker system prune --all --force --filter "until=168h" 2>/dev/null || true
          echo "Pruned Docker"
        fi

        # 5. Podman prune (if available)
        if command -v podman &>/dev/null; then
          podman system prune --all --force 2>/dev/null || true
          echo "Pruned Podman"
        fi

        # 6. Nix garbage collection
        nix-collect-garbage --delete-older-than ${toString cfg.nixKeepDays}d 2>/dev/null || true
        echo "Ran nix garbage collection"

        echo "=== Cleanup complete ==="
        df -h / | tail -1
      '';
      serviceConfig = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.disk-cleanup = {
      description = "Weekly disk cleanup timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun 03:00";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };

    # Keep journal size bounded
    services.journald.extraConfig = ''
      SystemMaxUse=${cfg.journalMaxSize}
    '';

    # Clean old tmp files via systemd-tmpfiles
    systemd.tmpfiles.rules = [
      "d /tmp 1777 root root ${cfg.tmpCleanupAge}"
    ];
  };
}
