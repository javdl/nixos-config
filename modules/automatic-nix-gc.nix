{ config, lib, pkgs, ... }:

# Disk-based automatic Nix garbage collection
#
# Unlike time-based GC, this checks disk space first and only runs
# when available space falls below a threshold.
#
# Features:
# - Configurable disk threshold
# - Build-time GC via min-free/max-free
# - Scheduled GC with disk space check
# - Low priority (nice 19, idle I/O)
# - Randomized delay to avoid thundering herd
# - Preserves recent generations

let
  cfg = config.services.automaticNixGC;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.automaticNixGC = {
    enable = mkEnableOption "disk-based automatic Nix garbage collection";

    minFreeGB = mkOption {
      type = types.int;
      default = 50;
      description = "Minimum free space in GiB before triggering GC during builds";
    };

    maxFreeGB = mkOption {
      type = types.int;
      default = 100;
      description = "Target free space in GiB after GC during builds";
    };

    scheduledThresholdGB = mkOption {
      type = types.int;
      default = 50;
      description = "Disk threshold in GiB for scheduled GC (only runs if below this)";
    };

    keepDays = mkOption {
      type = types.int;
      default = 14;
      description = "Keep generations newer than this many days";
    };

    schedule = mkOption {
      type = types.str;
      default = "daily";
      description = "Systemd calendar expression for when to check disk space";
    };

    randomizedDelaySec = mkOption {
      type = types.int;
      default = 1800;
      description = "Maximum random delay in seconds before running GC";
    };

    persistent = mkOption {
      type = types.bool;
      default = true;
      description = "Run GC on boot if scheduled time was missed";
    };
  };

  config = mkIf cfg.enable {
    # Build-time GC: trigger GC during builds when disk space is low
    nix.extraOptions = ''
      min-free = ${toString (cfg.minFreeGB * 1024 * 1024 * 1024)}
      max-free = ${toString (cfg.maxFreeGB * 1024 * 1024 * 1024)}
    '';

    # Disable default time-based GC (we use our own disk-based approach)
    nix.gc.automatic = lib.mkDefault false;

    # Scheduled disk-based GC service
    systemd.services.nix-gc-disk-based = {
      description = "Nix Garbage Collection (disk-based)";
      script = ''
        set -euo pipefail

        STORE_PATH="/nix/store"
        THRESHOLD_GB=${toString cfg.scheduledThresholdGB}
        KEEP_DAYS=${toString cfg.keepDays}

        # Get available space in GB
        AVAIL_GB=$(${pkgs.coreutils}/bin/df -BG "$STORE_PATH" | ${pkgs.gawk}/bin/awk 'NR==2 {gsub("G",""); print $4}')

        echo "Available space: ''${AVAIL_GB}GB, threshold: ''${THRESHOLD_GB}GB"

        if [ "$AVAIL_GB" -lt "$THRESHOLD_GB" ]; then
          echo "Below threshold, running garbage collection..."
          ${config.nix.package}/bin/nix-collect-garbage --delete-older-than ''${KEEP_DAYS}d
          echo "Garbage collection complete"

          # Report new available space
          NEW_AVAIL=$(${pkgs.coreutils}/bin/df -BG "$STORE_PATH" | ${pkgs.gawk}/bin/awk 'NR==2 {gsub("G",""); print $4}')
          echo "Available space after GC: ''${NEW_AVAIL}GB"
        else
          echo "Sufficient space available, skipping garbage collection"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        # Run at lowest CPU priority
        Nice = 19;
        # Run at idle I/O priority
        IOSchedulingClass = "idle";
        IOSchedulingPriority = 7;
      };
    };

    systemd.timers.nix-gc-disk-based = {
      description = "Timer for disk-based Nix Garbage Collection";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        RandomizedDelaySec = cfg.randomizedDelaySec;
        Persistent = cfg.persistent;
      };
    };
  };
}
