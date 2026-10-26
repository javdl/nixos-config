# Minimal headless profile for the DGX Sparks (spark, spark2).
#
# Not the Omarchy workstation profile. This file does not import
# users/joost/home-manager.nix, users/agent-clis.nix, or chezmoi.
# The only packages are mosh, tmux, iperf3, and herdr. Herdr's fleet node
# (service, fleet.toml, controller authorized_keys) comes from
# users/herdr-fleet.nix. Root-owned files (NAS automount, CX7 link, sshd
# fallback, linger) are synced into /etc on every activation by
# users/dgx-spark.nix. Both hosts switch to the GitHub flake nightly
# (users/home-auto-update.nix). The dsv41 TP2 cluster is one
# definition in users/dsv41-cluster.nix, kept off. The production server
# is Mia in users/dsv41-mia.nix: dsv41-mia.service on spark only. spark2
# has no model unit; the head starts rank 1 over ssh. Tailscale Serve
# stays dsv41-cluster-serve on spark. See docs/dgx-spark.md.
{ hostName }:
{ lib, pkgs, ... }:
{
  imports = [
    (import ../herdr-fleet.nix { currentSystemName = hostName; })
    (import ../dgx-spark.nix { currentSystemName = hostName; })
    (import ../dsv41-cluster.nix { inherit hostName; })
    (import ../dsv41-mia.nix { inherit hostName; })
    ../home-auto-update.nix
  ];

  # Explicit, so a switch cannot fall through to a changed module default.
  # Sybil head/worker/health/follow stay out of the generation. Mia is the
  # server. Flip both to roll back; see docs/dgx-spark.md.
  services.dsv41Cluster.enable = false;
  services.dsv41Mia.enable = true;

  services.homeAutoUpdate = {
    enable = true;
    flake = "github:javdl/nixos-config#homeConfigurations.${hostName}";
  };

  assertions = [
    {
      assertion = hostName == "spark" || hostName == "spark2";
      message = "users/joost/home-manager-spark.nix only applies to spark and spark2 (got ${hostName})";
    }
  ];

  home.username = "joost";
  home.homeDirectory = "/home/joost";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    herdr
    iperf3
    mosh
    tmux
  ];
}
