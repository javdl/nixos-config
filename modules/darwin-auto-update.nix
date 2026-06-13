{
  config,
  lib,
  pkgs,
  ...
}:

# nix-darwin auto-update — launchd equivalent of services.nixosAutoUpdate.
#
# Rebuilds the host from a flake on a daily schedule so headless macOS
# servers (argon, radon) stay current without manual intervention, mirroring
# the colleague Linux servers' 04:00 auto-update.
#
# Determinate Nix manages Nix itself (nix.enable = false on these hosts), so
# this uses a launchd daemon running `darwin-rebuild switch` rather than any
# nix-darwin nix tooling. launchd coalesces missed StartCalendarInterval
# events, so a machine that was asleep at the scheduled time runs once on wake.

let
  cfg = config.services.darwinAutoUpdate;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.services.darwinAutoUpdate = {
    enable = mkEnableOption "nix-darwin automatic updates from a flake";

    flake = mkOption {
      type = types.str;
      example = "github:javdl/nixos-config#argon";
      description = "Flake URI to rebuild from, e.g. github:javdl/nixos-config#<hostname>.";
    };

    hour = mkOption {
      type = types.int;
      default = 4;
      description = "Hour of day (local time, 0-23) to run the update.";
    };

    minute = mkOption {
      type = types.int;
      default = 0;
      description = "Minute of the hour to run the update.";
    };
  };

  config = mkIf cfg.enable {
    launchd.daemons.darwin-auto-update = {
      script = ''
        export PATH=/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin
        export HOME=/var/root
        echo "[$(date)] darwin-auto-update: rebuilding ${cfg.flake}"
        exec darwin-rebuild switch --flake ${cfg.flake} --no-write-lock-file
      '';
      serviceConfig = {
        RunAtLoad = false;
        StartCalendarInterval = [
          {
            Hour = cfg.hour;
            Minute = cfg.minute;
          }
        ];
        StandardOutPath = "/var/log/darwin-auto-update.log";
        StandardErrorPath = "/var/log/darwin-auto-update.log";
        LowPriorityIO = true;
        Nice = 10;
      };
    };
  };
}
