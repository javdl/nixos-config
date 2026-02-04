{
  description = "NixOS systems and tools by joost";

  nixConfig = {
    download-buffer-size = 536870912;  # 512 MiB, default is 64 MiB
  };

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

    # Secrets management using SOPS
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    hyprland.url = "github:hyprwm/Hyprland";

    # MicroVM support for isolated coding agents
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

  outputs = { self, nixpkgs, nixos-hardware, home-manager, darwin, ... }@inputs: let
    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = [
      # inputs.jujutsu.overlays.default
      # inputs.zig.overlays.default

      (final: prev:
        let
          # Import nixpkgs-unstable with allowUnfree enabled
          pkgs-unstable = import inputs.nixpkgs-unstable {
            system = prev.stdenv.hostPlatform.system;
            config.allowUnfree = true;
          };

          # grepai - semantic code search CLI tool
          grepaiVersion = "0.18.0";
          grepaiSources = {
            "x86_64-linux" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_linux_amd64.tar.gz";
              sha256 = "388058dfeb16a5ac1fe16c03e84322404096c37e952a0653502acb98a46645a7";
            };
            "aarch64-linux" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_linux_arm64.tar.gz";
              sha256 = "5669815fccb66b525397deeddc498e3797a802b1155afb1e09cd7e9f412ba44f";
            };
            "x86_64-darwin" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_darwin_amd64.tar.gz";
              sha256 = "03e06ab3d6f2434ce439bbb32be945274e1e9c138d5d994cbf70fb42cc0c57ab";
            };
            "aarch64-darwin" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_darwin_arm64.tar.gz";
              sha256 = "190c6e1571917ca6f2e4fef9a53d894f39c3a80219c9a552b31c086bb9b4fc4f";
            };
          };
          grepaiSource = grepaiSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for grepai: ${prev.stdenv.hostPlatform.system}");
        in {
          # grepai - semantic code search for AI coding assistants
          grepai = prev.stdenv.mkDerivation {
            pname = "grepai";
            version = grepaiVersion;

            src = prev.fetchurl {
              url = grepaiSource.url;
              sha256 = grepaiSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.gnutar ];

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp grepai $out/bin/
              chmod +x $out/bin/grepai
            '';

            meta = with prev.lib; {
              description = "Semantic code search CLI tool for AI coding assistants";
              homepage = "https://github.com/yoanbernabeu/grepai";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };
          # gh CLI on stable has bugs.
          gh = pkgs-unstable.gh;

          # Want the latest version of these
          nushell = pkgs-unstable.nushell;

          # Fix setproctitle test failures on macOS
          python3 = prev.python3.override {
            packageOverrides = pyFinal: pyPrev: {
              setproctitle = pyPrev.setproctitle.overridePythonAttrs (old: {
                doCheck = false;
              });
            };
          };

          python313 = prev.python313.override {
            packageOverrides = pyFinal: pyPrev: {
              setproctitle = pyPrev.setproctitle.overridePythonAttrs (old: {
                doCheck = false;
              });
            };
          };
        })
    ];

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
