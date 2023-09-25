{
  description = "NixOS systems and tools by joost";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Build a custom WSL installer
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # I think technically you're not supposed to override the nixpkgs
    # used by neovim but recently I had failures if I didn't pin to my
    # own. We can always try to remove that anytime.
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";

      # Only need unstable until the lpeg fix hits mainline, probably
      # not very long... can safely switch back for 23.11.
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Other packages
    zig.url = "github:mitchellh/zig-overlay";

    # Non-flakes
    nvim-treesitter.url = "github:nvim-treesitter/nvim-treesitter/v0.9.1";
    nvim-treesitter.flake = false;
    vim-copilot.url = "github:github/copilot.vim/v1.11.1";
    vim-copilot.flake = false;
  };

  outputs = { self, nixpkgs, home-manager, darwin, ... }@inputs: let
    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = [
      inputs.neovim-nightly-overlay.overlay
      inputs.zig.overlays.default
    ];

    mkSystem = import ./lib/mksystem.nix {
      inherit overlays nixpkgs inputs;
    };
  in {
    nixosConfigurations.vm-aarch64 = mkVM "vm-aarch64" {
      inherit nixpkgs home-manager;
      system = "aarch64-linux";
      user   = "joost";

      overlays = overlays ++ [(final: prev: {
        # Example of bringing in an unstable package:
        # open-vm-tools = inputs.nixpkgs-unstable.legacyPackages.${prev.system}.open-vm-tools;
      })];
    };

    nixosConfigurations.vm-aarch64-prl = mkVM "vm-aarch64-prl" rec {
      inherit overlays nixpkgs home-manager;
      system = "aarch64-linux";
      user   = "joost";
    };

    nixosConfigurations.vm-aarch64-prl = mkSystem "vm-aarch64-prl" rec {
      system = "aarch64-linux";
      user   = "joost";
    };

    nixosConfigurations.vm-aarch64-utm = mkSystem "vm-aarch64-utm" rec {
      system = "aarch64-linux";
      user   = "mitchellh";
    };

    nixosConfigurations.vm-intel = mkSystem "vm-intel" rec {
      system = "x86_64-linux";
      user   = "joost";
    };

    nixosConfigurations.wsl = mkSystem "wsl" {
      system = "x86_64-linux";
      user   = "joost";
      wsl    = true;
    };

    darwinConfigurations.macbook-pro-m1 = mkSystem "macbook-pro-m1" {
    nixosConfigurations.amd-nvidia = mkVM "amd-nvidia" rec {
      inherit nixpkgs home-manager overlays;
      system = "x86_64-linux";
      user   = "joost";
    };

    darwinConfigurations.macbook-pro-m1 = mkDarwin "macbook-pro-m1" {
      inherit darwin nixpkgs home-manager overlays;
      system = "aarch64-darwin";
      user   = "joost";
    };
  };
}
