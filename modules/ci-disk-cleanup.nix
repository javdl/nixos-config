{ config, lib, pkgs, ... }:

# CI disk cleanup: Docker pruning, journal vacuum, tmp cleanup, tool cache cleanup,
# runner work dir cleanup, pnpm/npm cache cleanup
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
      default = "/var/lib/github-runner-work";
      description = ''
        GitHub Actions runner work directory root (on persistent disk).
        Must match the per-runner `workDir` set in services.github-runners.
        The default `/run/github-runner` from upstream is tmpfs-backed and
        fills under load; we override it to use the data disk instead.
      '';
    };

    runnerRuntimeDir = mkOption {
      type = types.str;
      default = "/run/github-runner";
      description = ''
        Legacy tmpfs runtime dir where systemd still places the runner binary
        and a small _actions cache. Monitored for fullness as a safety net,
        but workspaces should not live here.
      '';
    };

    tmpfsThresholdPct = mkOption {
      type = types.int;
      default = 80;
      description = "Trigger tmpfs cleanup when /run usage exceeds this percentage";
    };

    runnerWorkCleanupAge = mkOption {
      type = types.int;
      default = 7;
      description = "Delete runner checkout/cache dirs older than this many days";
    };

    monitorIntervalMin = mkOption {
      type = types.int;
      default = 10;
      description = "How often the disk monitor runs (minutes)";
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
        # Also prune dangling volumes (not cleaned by docker system prune)
        ${pkgs.docker}/bin/docker volume prune --force 2>/dev/null || true
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

    # Clean stale runner work directories (repo checkouts, tool caches, pnpm stores)
    # Self-hosted runners persist data between jobs — this prevents unbounded growth
    systemd.services.ci-runner-work-cleanup = {
      description = "Clean stale GitHub Actions runner work directories";
      path = with pkgs; [ coreutils findutils gawk ];
      script = ''
        set -euo pipefail
        RUNNER_DIR="${cfg.runnerWorkDir}"
        AGE_DAYS=${toString cfg.runnerWorkCleanupAge}

        if [ ! -d "$RUNNER_DIR" ]; then
          echo "Runner dir $RUNNER_DIR not found, skipping"
          exit 0
        fi

        echo "=== Runner work directory cleanup (>''${AGE_DAYS}d) ==="
        BEFORE=$(du -sh "$RUNNER_DIR" 2>/dev/null | awk '{print $1}')
        echo "Before: $BEFORE"

        # Clean _tool caches (setup-node, setup-gcloud, etc. — re-downloaded on use)
        find "$RUNNER_DIR" -type d -name "_tool" -mtime +"$AGE_DAYS" -exec rm -rf {} + 2>/dev/null || true

        # Clean _temp directories
        find "$RUNNER_DIR" -type d -name "_temp" -not -empty -mtime +"$AGE_DAYS" -exec rm -rf {} + 2>/dev/null || true

        # Clean setup-pnpm global store caches (these get huge)
        find "$RUNNER_DIR" -type d -name "setup-pnpm" -mtime +"$AGE_DAYS" -exec rm -rf {} + 2>/dev/null || true

        # Within each runner dir, clean old repo checkouts
        for runner in "$RUNNER_DIR"/fuww-runner-*/; do
          [ -d "$runner" ] || continue
          for dir in "$runner"/*/; do
            [ -d "$dir" ] || continue
            basename=$(basename "$dir")
            # Skip runner internal directories
            case "$basename" in
              _actions|_PipelineMapping|_diag|_temp) continue ;;
            esac
            # Remove if older than threshold and not actively in use
            if [ "$(find "$dir" -maxdepth 0 -mtime +"$AGE_DAYS" 2>/dev/null)" ]; then
              echo "Removing stale work dir: $dir"
              rm -rf "$dir"
            fi
          done
        done

        # Clean npm/pnpm caches under the github-runner home
        for cache_dir in /home/github-runner/.npm /home/github-runner/.pnpm-store /home/github-runner/.cache/pnpm /home/github-runner/.local/share/pnpm; do
          if [ -d "$cache_dir" ]; then
            SIZE=$(du -sh "$cache_dir" 2>/dev/null | awk '{print $1}')
            echo "Cleaning $cache_dir ($SIZE)"
            rm -rf "$cache_dir"
          fi
        done

        AFTER=$(du -sh "$RUNNER_DIR" 2>/dev/null | awk '{print $1}')
        echo "After: $AFTER"
      '';
      serviceConfig = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.ci-runner-work-cleanup = {
      description = "Timer for runner work directory cleanup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = 900;
        Persistent = true;
      };
    };

    # Proactive disk space monitor — runs every 10 minutes
    # Cleans Docker, Actions tool cache, and nix store when disk is low.
    # Also monitors /run (tmpfs) since the upstream github-runner module places
    # runtime state there and any spillover (e.g., _actions/_temp) fills it fast.
    systemd.services.ci-disk-monitor = {
      description = "CI disk space monitor and emergency cleanup";
      after = [ "docker.service" ];
      path = with pkgs; [ coreutils gawk docker nix ];
      script = ''
        set -euo pipefail
        THRESHOLD=${toString cfg.diskThresholdGB}
        RUNNER_DIR="${cfg.runnerWorkDir}"
        RUNTIME_DIR="${cfg.runnerRuntimeDir}"
        TMPFS_PCT_THRESHOLD=${toString cfg.tmpfsThresholdPct}

        AVAIL_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
        TMPFS_USE_PCT=$(df --output=pcent /run | tail -1 | tr -d ' %')
        echo "Disk available: ''${AVAIL_GB}GB (threshold: ''${THRESHOLD}GB)"
        echo "Tmpfs /run usage: ''${TMPFS_USE_PCT}% (threshold: ''${TMPFS_PCT_THRESHOLD}%)"

        # Tmpfs cleanup: even though workspaces live on disk now, _actions caches
        # and tool downloads still land under $RUNTIME_DIR. Clear them aggressively
        # whenever /run gets crowded — they re-download on next use.
        if [ "$TMPFS_USE_PCT" -ge "$TMPFS_PCT_THRESHOLD" ]; then
          echo "=== TMPFS PRESSURE — clearing runtime caches ==="
          if [ -d "$RUNTIME_DIR" ]; then
            find "$RUNTIME_DIR" -type d -name "_actions" -exec rm -rf {} + 2>/dev/null || true
            find "$RUNTIME_DIR" -type d -name "_temp" -exec rm -rf {} + 2>/dev/null || true
            find "$RUNTIME_DIR" -type d -name "_tool" -exec rm -rf {} + 2>/dev/null || true
          fi
          NEW_PCT=$(df --output=pcent /run | tail -1 | tr -d ' %')
          echo "Tmpfs /run after cleanup: ''${NEW_PCT}%"
        fi

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
          docker volume prune --force 2>/dev/null || true
          echo "Cleaned Docker images, build cache, and volumes"

          # 3. Nix store GC
          nix-collect-garbage --delete-older-than 3d 2>/dev/null || true
          echo "Ran nix garbage collection"

          # 4. Clean old logs
          journalctl --vacuum-size=200M 2>/dev/null || true

          # 5. Truncate audit logs if they're large (auditd rotation can lag)
          if [ -f /var/log/audit/audit.log ]; then
            AUDIT_MB=$(du -sm /var/log/audit 2>/dev/null | awk '{print $1}')
            if [ "''${AUDIT_MB:-0}" -gt 500 ]; then
              echo "Audit logs are ''${AUDIT_MB}MB, truncating..."
              find /var/log/audit -name 'audit.log.*' -delete 2>/dev/null || true
              truncate -s 0 /var/log/audit/audit.log
              echo "Truncated audit logs"
            fi
          fi

          # 6. Clean npm/pnpm caches
          rm -rf /home/github-runner/.npm /home/github-runner/.pnpm-store 2>/dev/null || true
          rm -rf /home/github-runner/.cache/pnpm /home/github-runner/.local/share/pnpm 2>/dev/null || true

          # 7. Clean all runner work dirs (repos re-clone on next job)
          if [ -d "$RUNNER_DIR" ]; then
            for runner in "$RUNNER_DIR"/fuww-runner-*/; do
              [ -d "$runner" ] || continue
              for dir in "$runner"/*/; do
                [ -d "$dir" ] || continue
                case "$(basename "$dir")" in
                  _actions|_PipelineMapping|_diag) continue ;;
                esac
                rm -rf "$dir"
              done
            done
            echo "Cleaned all runner work directories"
          fi

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
        OnUnitActiveSec = "${toString cfg.monitorIntervalMin}m";
        AccuracySec = "1m";
      };
    };

    # Keep journal size bounded
    services.journald.extraConfig = ''
      SystemMaxUse=${cfg.journalMaxSize}
    '';

    # Clean old tmp files; pre-create runner workspace root with correct ownership
    # so the per-runner StateDirectory entries can be created on first start.
    systemd.tmpfiles.rules = [
      "d /tmp 1777 root root ${cfg.tmpCleanupAge}"
      "d ${cfg.runnerWorkDir} 0755 github-runner users -"
    ];
  };
}
