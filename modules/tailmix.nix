# tailmix - reach machines on more than one tailnet from a single host.
#
# Why this exists: bali is the Herdr controller and needs to reach personal
# machines (terra, radon) that live on a different tailnet. Tailscale node
# sharing cannot solve it — a machine "cannot be shared with a tag or accessed
# by tagged machines on another tailnet" (https://tailscale.com/kb/1084/sharing)
# and bali is a tagged device. tailmix instead runs one tsnet client per tailnet
# behind a single TUN, remaps each tailnet's peers into a local IPv4 range and
# answers MagicDNS with those addresses, so overlapping 100.64.0.0/10 space
# between the two tailnets stops being a problem.
#
# This module only runs the daemon. Profiles are added imperatively once per
# host, because each one consumes a tailnet auth key that must not live in the
# store:
#
#   tailmix profiles add personal --hostname bali --auth-key-file /run/keys/ts-personal
#   tailmix profiles list
#   tailmix status
#
# The unit mirrors upstream's service/tailmixd.service.in from the v0.1.9
# release tarball (state in /var/lib/tailmix, socket dir /var/run/tailmix).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.tailmix;

  # Unit fields shared with the Omarchy boxes, which get the same daemon from a
  # rendered unit file instead of this module. See lib/tailmix-service.nix.
  unit = import ../lib/tailmix-service.nix { inherit lib; };
in
{
  options.services.tailmix = {
    enable = lib.mkEnableOption "the tailmix multi-tailnet daemon";

    package = lib.mkPackageOption pkgs "tailmix" { };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "-verbose" ];
      description = "Extra flags appended to the tailmixd command line.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.services.tailmixd = {
      inherit (unit) description;
      documentation = [ unit.documentation ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = unit.serviceConfig // {
        ExecStart = unit.execStart {
          tailmixd = "${cfg.package}/bin/tailmixd";
          inherit (cfg) extraFlags;
        };
      };
    };
  };
}
