# NixOS configuration for user joost
{ pkgs, inputs, ... }:

{
  imports = [
    # Import common system configuration
    ../common/system.nix
  ];

  # User account configuration
  users.users.joost = {
    isNormalUser = true;
    home = "/home/joost";
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.fish;
    hashedPassword = "$6$nJOFfAkJl1RJMxUW$DuXpYNq7rc/TE7Awuyjv7vyOyzbUnHmxN3YN1Gz1DiAw363a9GkpEU6bU9MvYa94nXaP7oTSFbZegNb8kAcUm1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFB87It3cS6o8kgD/6r3R59KP2o1eOJz1bgLJl4syLX1 joost"
    ];
  };

  # User-specific system packages
  environment.systemPackages = with pkgs; [
    docker
    docker-compose
  ];

  # Load vim overlays
  nixpkgs.overlays = import ../../lib/overlays.nix ++ [
    (import ./vim.nix { inherit inputs; })
  ];
}
