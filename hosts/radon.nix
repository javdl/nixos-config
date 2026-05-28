{ config, pkgs, ... }: {
  # nix-darwin stateVersion. Host runs macOS Tahoe.
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

  # Run Tailscale like a server service on this Mac. The Homebrew LaunchAgent
  # starts tailscaled as the logged-in user, which exits because tailscaled
  # needs root on macOS.
  launchd.daemons.tailscaled = {
    serviceConfig = {
      ProgramArguments = [
        "/opt/homebrew/opt/tailscale/bin/tailscaled"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/opt/homebrew/var/log/tailscaled.log";
      StandardErrorPath = "/opt/homebrew/var/log/tailscaled.log";
    };
  };
}
