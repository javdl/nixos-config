# Nightly Home Manager switch for hosts that are neither NixOS nor nix-darwin
# (the DGX Sparks on Ubuntu). Same schedule as services.darwinAutoUpdate on
# radon and services.nixosAutoUpdate on the Linux servers: rebuild from the
# GitHub flake at 04:00, so a push to main reaches the host overnight.
#
# The run builds `<flake>.activationPackage`, points the Home Manager profile
# at it when it changed, and runs its activate script, which is what
# `home-manager switch` does. Activation always runs, so it also re-applies
# the root files of users/dgx-spark.nix when they have drifted.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.homeAutoUpdate;

  script = pkgs.writeShellScript "home-auto-update" ''
    set -euo pipefail
    export PATH=/nix/var/nix/profiles/default/bin:/usr/bin:/bin
    profile=${lib.escapeShellArg "${config.xdg.stateHome}/nix/profiles/home-manager"}
    link="$RUNTIME_DIRECTORY/generation"

    echo "home-auto-update: building ${cfg.flake}"
    # --refresh: GitHub refs are cached for an hour; take main as it is now.
    # The out-link is a GC root until the profile holds the generation.
    nix build --refresh --out-link "$link" ${lib.escapeShellArg "${cfg.flake}.activationPackage"}
    gen=$(readlink -f "$link")

    if [ "$(readlink -f "$profile" 2>/dev/null || true)" = "$gen" ]; then
      echo "home-auto-update: $gen is already current; activating to correct drift"
    else
      nix-env --profile "$profile" --set "$gen"
    fi
    "$gen/activate" --driver-version 1
  '';
in
{
  options.services.homeAutoUpdate = {
    enable = lib.mkEnableOption "a nightly Home Manager switch from a flake";

    flake = lib.mkOption {
      type = lib.types.str;
      example = "github:javdl/nixos-config#homeConfigurations.spark";
      description = "Flake attribute of this home configuration. `.activationPackage` is appended.";
    };

    dates = lib.mkOption {
      type = lib.types.str;
      default = "04:00";
      description = "systemd calendar expression for the update.";
    };

    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = "Random delay added to `dates`.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.home-auto-update = {
      Unit = {
        Description = "Switch Home Manager to ${cfg.flake}";
        # The run activates the generation that replaces this unit. Restarting
        # it from inside that activation would kill the run halfway.
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        RuntimeDirectory = "home-auto-update";
        ExecStart = "${script}";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.timers.home-auto-update = {
      Unit.Description = "Nightly Home Manager switch";
      Timer = {
        OnCalendar = cfg.dates;
        RandomizedDelaySec = cfg.randomizedDelaySec;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
