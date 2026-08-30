{
  config,
  lib,
  pkgs,
  ...
}:

# Weekly disk cleanup for dev servers
#
# Cleans: audit logs, journal, tmp files, and Docker/Podman data
# Prevents the disk-full incidents caused by runaway auditd logging

let
  cfg = config.services.diskCleanup;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.services.diskCleanup = {
    enable = mkEnableOption "weekly disk cleanup (logs, tmp, and containers)";

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
  };

  config = mkIf cfg.enable {
    # Weekly cleanup service
    systemd.services.disk-cleanup = {
      description = "Weekly disk cleanup (logs, tmp, and containers)";
      path = with pkgs; [
        coreutils
        gawk
        findutils
      ];
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
        # Keep this well clear of the fleet's 04:00 auto-update window.
        OnCalendar = "Sun 01:00";
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
