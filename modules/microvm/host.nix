# MicroVM host configuration module
#
# Sets up network bridge with NAT for MicroVMs to access the internet.
# Based on https://michael.stapelberg.ch/posts/2026-02-01-coding-agent-microvm-nix/
#
# Usage:
#   services.microvmHost = {
#     enable = true;
#     externalInterface = "enp1s0";
#   };

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.microvmHost;
in
{
  options.services.microvmHost = {
    enable = mkEnableOption "MicroVM host support with network bridge";

    bridgeName = mkOption {
      type = types.str;
      default = "microbr";
      description = "Name of the network bridge for MicroVMs";
    };

    bridgeAddress = mkOption {
      type = types.str;
      default = "192.168.83.1/24";
      description = "IP address and prefix length for the bridge interface";
    };

    externalInterface = mkOption {
      type = types.str;
      description = "External network interface for NAT (e.g., enp1s0)";
      example = "enp1s0";
    };
  };

  config = mkIf cfg.enable {
    # Use systemd-networkd for network configuration
    systemd.network.enable = true;

    # Create the bridge device
    systemd.network.netdevs."10-${cfg.bridgeName}" = {
      netdevConfig = {
        Kind = "bridge";
        Name = cfg.bridgeName;
      };
    };

    # Configure the bridge with static IP
    systemd.network.networks."10-${cfg.bridgeName}" = {
      matchConfig.Name = cfg.bridgeName;
      networkConfig = {
        Address = cfg.bridgeAddress;
        DHCPServer = false;
      };
      linkConfig.RequiredForOnline = "no";
    };

    # Assign TAP interfaces (vm-*) to the bridge
    systemd.network.networks."11-microvm-tap" = {
      matchConfig.Name = "vm-*";
      networkConfig.Bridge = cfg.bridgeName;
    };

    # Enable NAT for MicroVMs to access internet
    networking.nat = {
      enable = true;
      internalInterfaces = [ cfg.bridgeName ];
      externalInterface = cfg.externalInterface;
    };

    # Trust the bridge interface in the firewall
    networking.firewall.trustedInterfaces = [ cfg.bridgeName ];

    # Ensure IP forwarding is enabled (required for NAT)
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
    };
  };
}
