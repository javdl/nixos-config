# Minimal headless profile for the DGX Sparks (spark, spark2).
#
# Not the Omarchy workstation profile. This file does not import
# users/joost/home-manager.nix, users/agent-clis.nix, or chezmoi.
# The only packages are mosh, tmux, iperf3, and herdr. Herdr's fleet node
# (service, fleet.toml, controller authorized_keys) comes from
# users/herdr-fleet.nix. users/dgx-spark.nix renders the NAS and CX7 files
# for a one-time root install and appends radon's sparks public key.
# The dsv41 TP2 cluster is one definition in users/dsv41-cluster.nix: this
# host runs the unit for its own rank. See docs/dgx-spark.md.
{ hostName }:
{ lib, pkgs, ... }:
{
  imports = [
    (import ../herdr-fleet.nix { currentSystemName = hostName; })
    (import ../dgx-spark.nix { currentSystemName = hostName; })
    (import ../dsv41-cluster.nix { inherit hostName; })
  ];

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
