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

    # Secrets management using SOPS
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

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

          # beads_viewer (bv) - TUI for beads issue tracking
          bvVersion = "0.14.4";
          bvSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_linux_amd64.tar.gz";
              sha256 = "99151b125691f9cb8c2c7e8771cf96e0734918cbff6971d6578554181b80713c";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_linux_arm64.tar.gz";
              sha256 = "aa82889d81b4a730abe571a61d538b51735601c58aebda6231ff91d1a2951b58";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_darwin_amd64.tar.gz";
              sha256 = "0a938c563baad7bd1f50c0b44505c863afd6695eefab503cf554a65233a49c39";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_darwin_arm64.tar.gz";
              sha256 = "0b70990b1a38ffe6a70e9ab2cce3c353637dc137d8bddffa821fa84f77a6fa31";
            };
          };
          bvSource = bvSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for bv: ${prev.stdenv.hostPlatform.system}");

          # cass - coding agent session search
          # Releases removed from GitHub; source needs sibling repos to build.
          # Install via Homebrew instead: brew install dicklesworthstone/tap/cass
          cassVersion = "0.1.64";

          # beads (bd) - git-backed issue tracker for AI agents
          beadsVersion = "0.55.4";
          beadsSources = {
            "x86_64-linux" = {
              url = "https://github.com/steveyegge/beads/releases/download/v${beadsVersion}/beads_${beadsVersion}_linux_amd64.tar.gz";
              sha256 = "e0fa25456dd82890230eef17653448a0bf995104c78864be91c5ed84426a5f49";
            };
            "aarch64-linux" = {
              url = "https://github.com/steveyegge/beads/releases/download/v${beadsVersion}/beads_${beadsVersion}_linux_arm64.tar.gz";
              sha256 = "273c2a463e10778f3764e7119cf8d4ae014a208a9c1859e0e228633ce66cbeaf";
            };
            "x86_64-darwin" = {
              url = "https://github.com/steveyegge/beads/releases/download/v${beadsVersion}/beads_${beadsVersion}_darwin_amd64.tar.gz";
              sha256 = "39a371688b4e622e14eb5bc84f54f90ed7a9a2faac57861156811af4693f8284";
            };
            "aarch64-darwin" = {
              url = "https://github.com/steveyegge/beads/releases/download/v${beadsVersion}/beads_${beadsVersion}_darwin_arm64.tar.gz";
              sha256 = "18afdf4f562323a71687b2f7ed95c27750aee8d361b176a4a79caf176f00c0b9";
            };
          };
          beadsSource = beadsSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for beads: ${prev.stdenv.hostPlatform.system}");

          # dcg - destructive command guard
          dcgVersion = "0.4.0";
          dcgSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-x86_64-unknown-linux-gnu.tar.xz";
              sha256 = "1704a533f0e40ed12bac3c13273ac1e095e20c3eebed50cc6711f7073eaa505c";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-aarch64-unknown-linux-gnu.tar.xz";
              sha256 = "06d9d6358a470a1934265f95d0a1df95745e72cf9984a45fd3e373593b6bd0af";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-x86_64-apple-darwin.tar.xz";
              sha256 = "d843a97fa6eba1b69d287afa28fb9bfe4ef22d1539da786166237c4869ee93fa";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-aarch64-apple-darwin.tar.xz";
              sha256 = "2a0d594f1ec54b1a9453c376c4a9c6277ef548c869f60bac46cbd22928251e83";
            };
          };
          dcgSource = dcgSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for dcg: ${prev.stdenv.hostPlatform.system}");
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
          # bv - beads viewer TUI for issue tracking
          beads-viewer = prev.stdenv.mkDerivation {
            pname = "beads-viewer";
            version = bvVersion;

            src = prev.fetchurl {
              url = bvSource.url;
              sha256 = bvSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.gnutar ];

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp bv $out/bin/
              chmod +x $out/bin/bv
            '';

            meta = with prev.lib; {
              description = "Elegant TUI for the Beads issue tracking system";
              homepage = "https://github.com/Dicklesworthstone/beads_viewer";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # ubs - ultimate bug scanner for AI-assisted code quality
          ubs = prev.stdenv.mkDerivation {
            pname = "ubs";
            version = "5.0.6";

            src = prev.fetchurl {
              url = "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/v5.0.6/ubs";
              sha256 = "ebb31bf412a409a19a060f2587c2ea02f185c0bf695204db6c73ef7560d377ed";
            };

            dontUnpack = true;

            nativeBuildInputs = [ prev.makeWrapper ];

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/ubs
              chmod +x $out/bin/ubs
              wrapProgram $out/bin/ubs \
                --prefix PATH : ${prev.lib.makeBinPath [
                  prev.bash
                  prev.coreutils
                  prev.gnugrep
                  prev.gnused
                  prev.gawk
                  prev.findutils
                  prev.curl
                  prev.jq
                  prev.ripgrep
                  prev.ast-grep
                  prev.typos
                  prev.python3
                ]}
            '';

            meta = with prev.lib; {
              description = "AI-native code quality scanner detecting 1000+ bug patterns";
              homepage = "https://github.com/Dicklesworthstone/ultimate_bug_scanner";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # cass - coding agent session search TUI
          # Set to null; managed via Homebrew (brew install dicklesworthstone/tap/cass)
          cass = null;

          # ru - repo updater for syncing GitHub repositories
          repo-updater = prev.stdenv.mkDerivation {
            pname = "repo-updater";
            version = "1.2.1";

            src = prev.fetchurl {
              url = "https://github.com/Dicklesworthstone/repo_updater/releases/download/v1.2.1/ru";
              sha256 = "7dc465cc5a47102b68a983202b1026d451d767d76c969fe03c6eac1726bf3709";
            };

            dontUnpack = true;

            nativeBuildInputs = [ prev.makeWrapper ];

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/ru
              chmod +x $out/bin/ru
              wrapProgram $out/bin/ru \
                --prefix PATH : ${prev.lib.makeBinPath [
                  prev.bash
                  prev.coreutils
                  prev.git
                  prev.gh
                  prev.curl
                ]}
            '';

            meta = with prev.lib; {
              description = "Beautiful CLI tool for synchronizing GitHub repositories";
              homepage = "https://github.com/Dicklesworthstone/repo_updater";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # dcg - destructive command guard for AI coding agents
          destructive-command-guard = prev.stdenv.mkDerivation {
            pname = "destructive-command-guard";
            version = dcgVersion;

            src = prev.fetchurl {
              url = dcgSource.url;
              sha256 = dcgSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.xz ];

            unpackPhase = ''
              tar xJf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp dcg $out/bin/
              chmod +x $out/bin/dcg
            '';

            meta = with prev.lib; {
              description = "Safety hook for AI coding agents that blocks destructive commands";
              homepage = "https://github.com/Dicklesworthstone/destructive_command_guard";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # beads (bd) - git-backed issue tracker for AI agents
          beads = prev.stdenv.mkDerivation {
            pname = "beads";
            version = beadsVersion;

            src = prev.fetchurl {
              url = beadsSource.url;
              sha256 = beadsSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.gnutar ];

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp bd $out/bin/
              chmod +x $out/bin/bd
            '';

            meta = with prev.lib; {
              description = "Git-backed issue tracker for AI coding agents";
              homepage = "https://github.com/steveyegge/beads";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # cm - cass memory system (Linux only - no macOS binary available)
          cass-memory = if prev.stdenv.isLinux && prev.stdenv.hostPlatform.system == "x86_64-linux" then prev.stdenv.mkDerivation {
            pname = "cass-memory";
            version = "0.2.3";

            src = prev.fetchurl {
              url = "https://github.com/Dicklesworthstone/cass_memory_system/releases/download/v0.2.3/cass-memory-linux-x64";
              sha256 = "c1cf33be88ca819f8c457f4519334fa99727da42e29832c71e99fd423f1a29f4";
            };

            dontUnpack = true;

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/cm
              chmod +x $out/bin/cm
            '';

            meta = with prev.lib; {
              description = "Procedural memory system for AI coding agents";
              homepage = "https://github.com/Dicklesworthstone/cass_memory_system";
              license = licenses.mit;
              platforms = [ "x86_64-linux" ];
            };
          } else null;

          # gh CLI on stable has bugs.
          gh = pkgs-unstable.gh;

          # Want the latest version of these
          nushell = pkgs-unstable.nushell;

          # Fix setproctitle test failures on macOS
          # Fix aiohttp test_base_ctor hostname assertion failure in Nix sandbox
          python3 = prev.python3.override {
            packageOverrides = pyFinal: pyPrev: {
              setproctitle = pyPrev.setproctitle.overridePythonAttrs (old: {
                doCheck = false;
              });
              aiohttp = pyPrev.aiohttp.overridePythonAttrs (old: {
                disabledTests = (old.disabledTests or []) ++ [ "test_base_ctor" ];
              });
            };
          };

          python313 = prev.python313.override {
            packageOverrides = pyFinal: pyPrev: {
              setproctitle = pyPrev.setproctitle.overridePythonAttrs (old: {
                doCheck = false;
              });
              aiohttp = pyPrev.aiohttp.overridePythonAttrs (old: {
                disabledTests = (old.disabledTests or []) ++ [ "test_base_ctor" ];
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
