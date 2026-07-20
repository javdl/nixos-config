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
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

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
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-26.05";
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

    # Hermes Agent — personal AI gateway (Telegram/Discord/Slack + cron).
    # Exposes nixosModules.default for declarative system-service deployment.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      home-manager,
      darwin,
      disko,
      ...
    }@inputs:
    let
      # Overlays is the list of overlays we want to apply from flake inputs.
      overlays = import ./lib/overlays.nix { inherit inputs; };

      mkSystem = import ./lib/mksystem.nix {
        inherit overlays nixpkgs inputs;
      };

      # Systems we expose dev-tooling outputs (formatter / checks / devShells) for.
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # nixpkgs with our overlays applied, used only for the tooling outputs below.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system overlays;
          config.allowUnfree = true;
        };

      # Standard x86_64-linux auto-updating server (colleague dev boxes etc.).
      mkServer =
        name: user:
        mkSystem name {
          system = "x86_64-linux";
          inherit user;
          server = true;
        };

      # Standard aarch64-darwin workstation for joost.
      mkDarwin =
        name:
        mkSystem name {
          system = "aarch64-darwin";
          user = "joost";
          darwin = true;
        };
    in
    {
      # `nix fmt` — formats this repo's own Nix sources only. Skips vendored trees
      # (mcp_agent_mail, skills, .claude worktrees), the dead all-comment
      # modules/programs.nix (not valid standalone Nix) and truncated
      # users/music/autostart.nix, and the machine-generated lib/overlays.nix
      # (rewritten wholesale by the tool-updater automation — not hand-formatted).
      formatter = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        pkgs.writeShellApplication {
          name = "nixfmt-repo";
          runtimeInputs = [
            pkgs.nixfmt
            pkgs.findutils
          ];
          text = ''
            if [ "$#" -gt 0 ] && [ "$*" != "." ]; then
              exec nixfmt "$@"
            fi
            find flake.nix lib modules hosts users -name '*.nix' \
              ! -name programs.nix \
              ! -path '*/music/autostart.nix' \
              ! -name overlays.nix \
              -print0 | xargs -0 nixfmt
          '';
        }
      );

      # `nix develop` — pinned contributor toolchain for working on this flake.
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              nixfmt
              statix
              deadnix
              sops
              ssh-to-age
              age
            ];
          };
        }
      );

      # `nix flake check` — format gate over the repo's own Nix sources. Lints
      # (statix/deadnix) live in the devShell but are kept out of checks for now to
      # avoid blocking on pre-existing legacy findings.
      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          format =
            pkgs.runCommandLocal "check-nixfmt"
              {
                nativeBuildInputs = [
                  pkgs.nixfmt
                  pkgs.findutils
                ];
              }
              ''
                cd ${self}
                if ! find flake.nix lib modules hosts users -name '*.nix' \
                  ! -name programs.nix \
                  ! -path '*/music/autostart.nix' \
                  ! -name overlays.nix \
                  -print0 | xargs -0 nixfmt --check; then
                  echo "Nix files are not formatted. Run 'nix fmt' to fix." >&2
                  exit 1
                fi
                touch $out
              '';
        }
      );

      nixosConfigurations.vm-aarch64 = mkSystem "vm-aarch64" {
        system = "aarch64-linux";
        user = "joost";
      };

      # vm-aarch64-prl removed — hosts/vm-aarch64-prl.nix does not exist

      nixosConfigurations.vm-aarch64-utm = mkSystem "vm-aarch64-utm" rec {
        system = "aarch64-linux";
        user = "joost";
      };

      nixosConfigurations.vm-intel = mkSystem "vm-intel" rec {
        system = "x86_64-linux";
        user = "joost";
      };

      nixosConfigurations.wsl = mkSystem "wsl" {
        system = "x86_64-linux";
        user = "joost";
        wsl = true;
      };

      nixosConfigurations.fumusic = mkSystem "fumusic" rec {
        system = "x86_64-linux";
        user = "joost";
      };

      nixosConfigurations.fu095 = mkSystem "fu095" rec {
        system = "x86_64-linux";
        user = "joost";
      };

      nixosConfigurations.fu137 = mkSystem "fu137" rec {
        system = "x86_64-linux";
        user = "joost";
        raphael = true;
        pstate = true; # for modern AMD cpu's
        zenpower = true; # for modern AMD cpu's
      };

      nixosConfigurations.j7 = mkSystem "j7" rec {
        system = "x86_64-linux";
        user = "joost";
        raphael = true;
        pstate = true;
        zenpower = true;
      };

      # j9 is Arch Linux (Omarchy) — managed via homeConfigurations."j9" below,
      # not as a nixosConfiguration.

      nixosConfigurations.github-runner = mkSystem "github-runner" {
        system = "x86_64-linux";
        user = "joost";
      };

      nixosConfigurations.github-runner-02 = mkSystem "github-runner-02" {
        system = "x86_64-linux";
        user = "github-runner";
        server = true;
      };

      nixosConfigurations.github-runner-03 = mkSystem "github-runner-03" {
        system = "x86_64-linux";
        user = "github-runner";
        server = true;
      };

      nixosConfigurations.github-runner-04 = mkSystem "github-runner-04" {
        system = "x86_64-linux";
        user = "github-runner";
        server = true;
      };

      nixosConfigurations.github-runner-05 = mkSystem "github-runner-05" {
        system = "x86_64-linux";
        user = "github-runner";
        server = true;
      };

      nixosConfigurations.github-runner-06 = mkSystem "github-runner-06" {
        system = "x86_64-linux";
        user = "github-runner";
        server = true;
      };

      # Agent dev box running rondo (autonomous Claude Code agent). Reuses the
      # decommissioned github-runner-01 box. See modules/agent-dev-box.nix and
      # users/agent-jay/ — both designed to scale to more jay machines and new
      # agent users.
      nixosConfigurations.agent-jay-01 = mkSystem "agent-jay-01" {
        system = "x86_64-linux";
        user = "agent-jay";
        server = true;
      };

      nixosConfigurations.loom = mkSystem "loom" {
        system = "x86_64-linux";
        user = "joost";
        server = true;
      };

      # loom's replacement on a repurposed EX63 runner box (donor: one of
      # github-runner-03..06). Loom stays up until bali is verified;
      # hermes stays disabled on bali until cutover (hosts/bali.nix).
      nixosConfigurations.bali = mkSystem "bali" {
        system = "x86_64-linux";
        user = "joost";
        server = true;
      };

      # FashionUnited company-wide hermes-agent host.
      # Clone of loom's hermes-agent setup; see Plans/check-the-plan-for-misty-turtle.md.
      nixosConfigurations.hermes-fu = mkSystem "hermes-fu" {
        system = "x86_64-linux";
        user = "agent";
        server = true;
      };

      nixosConfigurations.joostclaw = mkSystem "joostclaw" {
        system = "x86_64-linux";
        user = "joost";
        server = true;
        hmConfig = "home-manager-joostclaw";
      };

      # Colleague AI dev servers (robot-themed names)
      nixosConfigurations.desmondroid = mkServer "desmondroid" "desmond";

      nixosConfigurations.jacksonator = mkServer "jacksonator" "jackson";

      nixosConfigurations.peterbot = mkServer "peterbot" "peter";

      nixosConfigurations.rajbot = mkServer "rajbot" "rajesh";

      nixosConfigurations.jeevanator = mkServer "jeevanator" "jeevan";

      nixosConfigurations.lennardroid = mkServer "lennardroid" "lennard";

      # All aarch64-darwin workstations share one definition (see mkDarwin).
      darwinConfigurations = nixpkgs.lib.genAttrs [
        "fu129"
        "fu146"
        "j8"
        "macbook-pro-m1"
        "macbook-air-m1"
        "mac-studio-m1"
        "mac-studio-m2"
        "argon"
        "radon"
        "mac-mini-m2"
        "mac-mini-m4"
        "macbook-air-m4"
        "crescendo"
      ] mkDarwin;

      # Home Manager configuration for GitHub runner on Ubuntu
      homeConfigurations."githubrunner" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = overlays;
        };
        modules = [
          ./users/githubrunner/home-manager.nix
          # mise (dev tool / runtime version manager) on every machine
          ({ pkgs, ... }: { home.packages = [ pkgs.mise ]; })
        ];
      };

      # Home Manager configuration for j9 (standalone, non-NixOS Linux - Arch/Omarchy)
      # Omarchy package lists: ~/.local/share/omarchy/install/omarchy-{base,other}.packages
      # Wayland/Hyprland tools are managed by Omarchy via pacman, not Nix
      homeConfigurations."j9" =
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = overlays;
            config.allowUnfree = true;
          };
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit inputs;
          };
          modules = [
            (import ./users/joost/home-manager.nix {
              isWSL = false;
              inherit inputs;
              currentSystemName = "j9";
            })
            ({ lib, pkgs, ... }: {
              nixpkgs.config.allowUnfree = true;
              home.username = "joost";
              home.homeDirectory = "/home/joost";

              # Additional packages from Omarchy that complement the Nix setup
              # These are CLI tools that work alongside Omarchy without conflicting
              home.packages = with pkgs; [
                gum # Terminal UI toolkit for shell scripts
                tldr # Simplified man pages
                mpv # Media player
                playerctl # Media player control (MPRIS)
                localsend # Local file sharing (LAN)
                inxi # System information tool
                mise # Dev tool / runtime version manager
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
      homeConfigurations."omarchy" =
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = overlays;
            config.allowUnfree = true;
          };
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit inputs;
          };
          modules = [
            (import ./users/joost/home-manager.nix {
              isWSL = false;
              inherit inputs;
            })
            ({ lib, pkgs, ... }: {
              nixpkgs.config.allowUnfree = true;
              home.username = "joost";
              home.homeDirectory = "/home/joost";

              # mise (dev tool / runtime version manager) on every machine
              home.packages = [ pkgs.mise ];

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
