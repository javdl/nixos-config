{ config, pkgs, ... }: {
  # nix-darwin stateVersion. Host runs macOS Tahoe.
  system.stateVersion = 6;

  # This makes it work with the Determinate Nix installer
  ids.gids.nixbld = 30000;

  # Set the primary user for homebrew and other user-specific settings
  system.primaryUser = "joost";

  # Don't let nix-darwin manage nix configuration since we use Determinate
  nix.settings = { };

  # Prevent nix-darwin from managing nix.conf
  environment.etc."nix/nix.conf".enable = false;

  imports = [
    ./mac-shared.nix
    ../modules/darwin-auto-update.nix
    ../modules/darwin-nix-gc.nix
    ../modules/darwin-tailscaled.nix
  ];

  # Stay current: rebuild from the GitHub flake daily (launchd equivalent of
  # the colleague Linux servers' services.nixosAutoUpdate at 04:00).
  services.darwinAutoUpdate = {
    enable = true;
    flake = "github:javdl/nixos-config#radon";
  };

  # Keep the Nix store from growing unbounded — Determinate does no auto-GC.
  services.darwinNixGC.enable = true;

  # Hardened headless Tailscale (replaces the inline launchd daemon). Persistent
  # state, userspace networking (required on macOS without macsys), joost as
  # operator (no sudo for `tailscale ...`). Place an auth key at the path below
  # (mode 0600 root) to enable unattended re-auth after reboots/rebuilds.
  services.darwinTailscaled = {
    enable = true;
    operator = "joost";
    authKeyFile = "/etc/tailscale/authkey";
  };
}
