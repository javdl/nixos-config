{ config, lib, pkgs, ... }:

# Scheduled Nix garbage collection for nix-darwin hosts — the macOS
# counterpart of services.automaticNixGC on the Linux servers.
#
# Determinate Nix (nix.enable = false) performs no automatic GC, so the store
# grows unbounded, especially once daily auto-updates are running. This
# launchd daemon prunes generations older than keepDays on a weekly schedule
# at low CPU/I/O priority. Time-based (not disk-threshold) since these hosts
# don't need the elaborate disk-pressure logic the CI runners use.

let
  cfg = config.services.darwinNixGC;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.darwinNixGC = {
    enable = mkEnableOption "scheduled Nix garbage collection (launchd)";

    keepDays = mkOption {
      type = types.int;
      default = 14;
      description = "Delete store paths from generations older than this many days.";
    };

    weekday = mkOption {
      type = types.int;
      default = 0;
      description = "Day of week to run GC (launchd Weekday; 0 = Sunday).";
    };

    hour = mkOption {
      type = types.int;
      default = 3;
      description = "Hour of day (local time, 0-23) to run GC.";
    };
  };

  config = mkIf cfg.enable {
    launchd.daemons.nix-gc = {
      script = ''
        export PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin
        echo "[$(date)] nix-gc: collecting garbage older than ${toString cfg.keepDays}d"
        exec nix-collect-garbage --delete-older-than ${toString cfg.keepDays}d
      '';
      serviceConfig = {
        RunAtLoad = false;
        StartCalendarInterval = [
          { Weekday = cfg.weekday; Hour = cfg.hour; Minute = 0; }
        ];
        StandardOutPath = "/var/log/nix-gc.log";
        StandardErrorPath = "/var/log/nix-gc.log";
        LowPriorityIO = true;
        Nice = 19;
      };
    };
  };
}
