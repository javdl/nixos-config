{ config, pkgs, ... }: {
  imports =
    [
      ./mac-shared.nix
      ../modules/cachix.nix
    ];
  # Set in Sept 2024 as part of the macOS Sequoia release.
  system.stateVersion = 5;

  # This makes it work with the Determinate Nix installer
  ids.gids.nixbld = 30000;

  # Set the primary user for homebrew and other user-specific settings
  system.primaryUser = "joost";

  # Don't let nix-darwin manage nix configuration since we use Determinate
  nix.settings = {};

  # Prevent nix-darwin from managing nix.conf
  environment.etc."nix/nix.conf".enable = false;

  imports =
    [
      ./mac-shared.nix
    ];

    # Enable tailscale. We manually authenticate when we want with
    # "sudo tailscale up". If you don't use tailscale, you should comment
    # out or delete all of this.
    services.tailscale.enable = true;
}
