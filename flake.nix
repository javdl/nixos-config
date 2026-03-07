{
  description = "NixOS systems and tools by joost";

  # download-buffer-size is set daemon-side:
  # - macOS: via nix.custom.conf in mac-shared.nix
  # - NixOS: via nix.settings in cachix.nix
  # Setting it here in nixConfig causes "not a trusted user" warnings on macOS.

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Build a custom WSL installer
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # snapd
    nix-snapd.url = "github:nix-community/nix-snapd";
    nix-snapd.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fh.url = "https://flakehub.com/f/DeterminateSystems/fh/*";

    # Declarative disk partitioning (used by nixos-anywhere)
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management using SOPS
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # OpenClaw AI assistant gateway (used on joostclaw server)
    nix-openclaw.url = "github:openclaw/nix-openclaw";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    hyprland.url = "github:hyprwm/Hyprland";

    # I think technically you're not supposed to override the nixpkgs
    # used by neovim but recently I had failures if I didn't pin to my
    # own. We can always try to remove that anytime.
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
    };

    # Other packages
    # jujutsu.url = "github:martinvonz/jj";
    # zig.url = "github:mitchellh/zig-overlay";

  };

  outputs = { self, nixpkgs, nixos-hardware, home-manager, darwin, disko, ... }@inputs: let
    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = import ./lib/overlays.nix { inherit inputs; };

    mkSystem = import ./lib/mksystem.nix {
      inherit overlays nixpkgs inputs;
    };
  in {
    nixosConfigurations.vm-aarch64 = mkSystem "vm-aarch64" {
      system = "aarch64-linux";
      user   = "joost";
    };

    nixosConfigurations.vm-aarch64-prl = mkSystem "vm-aarch64-prl" rec {
      system = "aarch64-linux";
      user   = "joost";
    };

    nixosConfigurations.vm-aarch64-utm = mkSystem "vm-aarch64-utm" rec {
      system = "aarch64-linux";
      user   = "joost";
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

    nixosConfigurations.fumusic = mkSystem "fumusic" rec {
      system = "x86_64-linux";
      user   = "joost";
    };


    nixosConfigurations.fu095 = mkSystem "fu095" rec {
      system = "x86_64-linux";
      user   = "joost";
    };

    darwinConfigurations.fu129 = mkSystem "fu129" {
      system = "aarch64-darwin";
      user   = "joost";
      darwin = true;
    };

    nixosConfigurations.fu137 = mkSystem "fu137" rec {
      system = "x86_64-linux";
      user   = "joost";
      raphael = true;
      pstate = true; # for modern AMD cpu's
      zenpower = true; # for modern AMD cpu's
    };

    darwinConfigurations.fu146 = mkSystem "fu146" {
      system = "aarch64-darwin";
      user   = "joost";
      darwin = true;
    };

    nixosConfigurations.j7 = mkSystem "j7" rec {
      system = "x86_64-linux";
      user   = "joost";
      raphael = true;
      pstate = true;
      zenpower = true;
    };

    darwinConfigurations.j8 = mkSystem "j8" {
      system = "aarch64-darwin";
      user   = "joost";
      darwin = true;
    };

    nixosConfigurations.j9 = mkSystem "j9" rec {
      system = "x86_64-linux";
      user   = "joost";
#      raphael = true;
#      pstate = true;
#      zenpower = true;
    };

    nixosConfigurations.github-runner = mkSystem "github-runner" {
      system = "x86_64-linux";
      user   = "joost";
    };

    nixosConfigurations.github-runner-01 = mkSystem "github-runner-01" {
      system = "x86_64-linux";
      user   = "github-runner";
      server = true;
    };

    nixosConfigurations.github-runner-02 = mkSystem "github-runner-02" {
      system = "x86_64-linux";
      user   = "github-runner";
      server = true;
    };

    nixosConfigurations.hetzner-dev = mkSystem "hetzner-dev" {
      system = "x86_64-linux";
      user   = "joost";
      server = true;
    };

    nixosConfigurations.loom = mkSystem "loom" {
      system = "x86_64-linux";
      user   = "joost";
      server = true;
    };

    nixosConfigurations.joostclaw = mkSystem "joostclaw" {
      system = "x86_64-linux";
      user   = "joost";
      server = true;
    };

    # Colleague AI dev servers (robot-themed names)
    nixosConfigurations.desmondroid = mkSystem "desmondroid" {
      system = "x86_64-linux";
      user   = "desmond";
      server = true;
    };

    nixosConfigurations.jacksonator = mkSystem "jacksonator" {
      system = "x86_64-linux";
      user   = "jackson";
      server = true;
    };

    nixosConfigurations.peterbot = mkSystem "peterbot" {
      system = "x86_64-linux";
      user   = "peter";
      server = true;
    };

    nixosConfigurations.rajbot = mkSystem "rajbot" {
      system = "x86_64-linux";
      user   = "rajesh";
      server = true;
    };

    nixosConfigurations.jeevanator = mkSystem "jeevanator" {
      system = "x86_64-linux";
      user   = "jeevan";
      server = true;
    };

    nixosConfigurations.lennardroid = mkSystem "lennardroid" {
      system = "x86_64-linux";
      user   = "lennard";
      server = true;
    };

    darwinConfigurations.macbook-pro-m1 = mkSystem "macbook-pro-m1" {
      system = "aarch64-darwin";
      user   = "joost";
      darwin = true;
    };

    darwinConfigurations.macbook-air-m1 = mkSystem "macbook-air-m1" {
      system = "aarch64-darwin";
      user   = "joost";
      darwin = true;
    };

    darwinConfigurations.mac-studio-m1 = mkSystem "mac-studio-m1" {
      system = "aarch64-darwin";
      user   = "joost";
      darwin = true;
    };

    darwinConfigurations.mac-studio-m2 = mkSystem "mac-studio-m2" {
      system = "aarch64-darwin";
      user   = "joost";
      darwin = true;
    };

    darwinConfigurations.mac-mini-m2 = mkSystem "mac-mini-m2" {
      system = "aarch64-darwin";
      user   = "joost";
      darwin = true;
    };

    darwinConfigurations.mac-mini-m4 = mkSystem "mac-mini-m4" {
      system = "aarch64-darwin";
      user   = "joost";
      darwin = true;
    };

    darwinConfigurations.macbook-air-m4 = mkSystem "macbook-air-m4" {
      system = "aarch64-darwin";
      user   = "joost";
      darwin = true;
    };

    darwinConfigurations.crescendo = mkSystem "crescendo" {
      system = "aarch64-darwin";
      user   = "joost";
      darwin = true;
    };

    # Home Manager configuration for GitHub runner on Ubuntu
    homeConfigurations."githubrunner" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = overlays;
      };
      modules = [
        ./users/githubrunner/home-manager.nix
      ];
    };

    # Home Manager configuration for j9 (standalone, non-NixOS Linux - Arch/Omarchy)
    # Omarchy package lists: ~/.local/share/omarchy/install/omarchy-{base,other}.packages
    # Wayland/Hyprland tools are managed by Omarchy via pacman, not Nix
    homeConfigurations."j9" = let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = overlays;
        config.allowUnfree = true;
      };
    in home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
      };
      modules = [
        (import ./users/joost/home-manager.nix { isWSL = false; inherit inputs; })
        ({ lib, pkgs, ... }: {
          nixpkgs.config.allowUnfree = true;
          home.username = "joost";
          home.homeDirectory = "/home/joost";

          # Additional packages from Omarchy that complement the Nix setup
          # These are CLI tools that work alongside Omarchy without conflicting
          home.packages = with pkgs; [
            gum           # Terminal UI toolkit for shell scripts
            tldr          # Simplified man pages
            mpv           # Media player
            playerctl     # Media player control (MPRIS)
            localsend     # Local file sharing (LAN)
            inxi          # System information tool
            # Wayland tools managed by Omarchy: hyprland, waybar, mako, etc.
          ];

          # Protect Omarchy-managed directories
          home.file.".config/omarchy".enable = false;
          home.file.".config/hypr".enable = false;
          home.file.".config/alacritty".enable = false;
          home.file.".config/btop/themes".enable = false;

          # Disable nixpkgs module's <nixpkgs> lookup for pure evaluation
          _module.args.pkgsPath = lib.mkForce nixpkgs;
        })
      ];
    };

    # Home Manager configuration for Omarchy (standalone, non-NixOS Linux)
    homeConfigurations."omarchy" = let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = overlays;
        config.allowUnfree = true;
      };
    in home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
      };
      modules = [
        (import ./users/joost/home-manager.nix { isWSL = false; inherit inputs; })
        ({ lib, ... }: {
          nixpkgs.config.allowUnfree = true;
          home.username = "joost";
          home.homeDirectory = "/home/joost";

          # Protect Omarchy-managed directories
          home.file.".config/omarchy".enable = false;
          home.file.".config/hypr".enable = false;
          home.file.".config/alacritty".enable = false;
          home.file.".config/btop/themes".enable = false;

          # Disable nixpkgs module's <nixpkgs> lookup for pure evaluation
          _module.args.pkgsPath = lib.mkForce nixpkgs;
        })
      ];
    };
  };
}
