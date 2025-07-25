{ config, lib, pkgs, ... }:

{
  # Install cachix CLI tool
  environment.systemPackages = [ pkgs.cachix ];

  # Configure Nix settings for caches
  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      "https://javdl-nixos-config.cachix.org"
      "https://devenv.cachix.org"
    ] ++ lib.optionals pkgs.stdenv.isLinux [
      "https://hyprland.cachix.org"
    ];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "javdl-nixos-config.cachix.org-1:6xuHXHavvpdfBLQq+RzxDAMxhWkea0NaYvLtDssDJIU="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "ai.cachix.org-1:yfTpKFKUOky7iJsfw4n9UV+Fy7JqEJNRJ8rDYX2WB8s="
    ] ++ lib.optionals pkgs.stdenv.isLinux [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];

    # Trust users to manage the Nix store
    trusted-users = [ "joost" "root" ];
  };
}