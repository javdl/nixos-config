{ config, pkgs, ... }: {

  # Mac Studio M1 office desk Joost
  networking.hostName = "fu146";

  nix.useDaemon = true;

  imports =
    [
      ./mac-shared.nix
    ];

    services.tailscale.enable = true;
}
