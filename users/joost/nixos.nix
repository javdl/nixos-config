{ pkgs, inputs, ... }:

{
  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/fish" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Since we're using fish as our shell
  programs.fish.enable = true;

  users.users.joost = {
    isNormalUser = true;
    home = "/home/joost";
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.fish;
    hashedPassword = "1ea9d598690f5ca5119b2a60b0f0f3b30b78deca60281e5eec938933de1e604b12e00d7987c1ff88a2fd5177d6659923e08a22065f75fe02bf8cd94c2f85bd25";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFB87It3cS6o8kgD/6r3R59KP2o1eOJz1bgLJl4syLX1 joost"
    ];
  };

  nixpkgs.overlays = import ../../lib/overlays.nix ++ [
    (import ./vim.nix { inherit inputs; })
  ];
}
