{
  description = "NixOS systems and tools by joost";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    # Determinate Nix pilot on bali, the dedicated full-flake evaluation runner.
    # Do not make this input follow nixpkgs: the upstream module deliberately
    # pins the package set used for its pre-built FlakeHub artifacts.
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

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

    # I think technically you're not supposed to override the nixpkgs
    # used by neovim but recently I had failures if I didn't pin to my
    # own. We can always try to remove that anytime.
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
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

      # Hosts excluded from the checks.eval-hosts gate because they do not evaluate
      # today. Keep this list empty; every entry is a tracked break, not a waiver.
      # Empty since 2026-07-28, when the two aarch64-linux VM hosts were retired.
      knownBrokenHosts = [ ];

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

      # Standalone Home Manager for Arch/Omarchy boxes (non-NixOS Linux).
      # Omarchy remains the owner of desktop packages and configuration; this
      # profile only layers complementary Nix-managed tooling on top.
      mkOmarchyHome =
        {
          hostName,
          extraPackages,
        }:
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
              isOmarchy = true;
              inherit inputs;
              currentSystemName = hostName;
            })
            # Same agent CLI toolset the NixOS/Darwin hosts get from
            # lib/mksystem.nix; this profile has no system layer to inherit it.
            ./users/agent-clis.nix
            (
              { lib, pkgs, ... }:
              {
                nixpkgs.config.allowUnfree = true;
                home.username = "joost";
                home.homeDirectory = "/home/joost";

                home.packages = extraPackages pkgs;

                # Protect Omarchy-managed directories. Program modules that
                # generate files below these paths are disabled by isOmarchy in
                # users/joost/home-manager.nix.
                home.file.".config/omarchy".enable = false;
                home.file.".config/hypr".enable = false;
                home.file.".config/alacritty".enable = false;
                home.file.".config/foot".enable = false;
                home.file.".config/ghostty".enable = false;
                home.file.".config/kitty".enable = false;
                home.file.".config/btop/themes".enable = false;

                # Disable nixpkgs module's <nixpkgs> lookup for pure evaluation
                _module.args.pkgsPath = lib.mkForce nixpkgs;
              }
            )
          ];
        };

      # Packages layered on top of Quattro's pacman set on every Omarchy box.
      # Keep this list in sync with omarchyManagedPackageNames in
      # users/joost/home-manager.nix: anything Quattro ships must not appear here.
      omarchyExtraPackages = pkgs: [
        pkgs.playerctl
        # Local-inference helper. CPU-only, no CUDA linkage: Nix-built CUDA
        # binaries cannot reach Arch's driver libs without nixGL, so the GPU
        # runtimes (ollama-cuda, nvidia-container-toolkit) come from pacman.
        # See docs/fu137-local-inference.md.
        pkgs.gollama
        # mosh is not an Omarchy/pacman-managed package, so Nix may own it here.
        # NixOS and Darwin hosts get mosh from lib/mksystem.nix; this standalone
        # Home Manager profile has no system layer, so it carries its own copy.
        pkgs.mosh
        # Multi-tailnet daemon. Only the binaries come from here; the unit is
        # rendered by users/joost/home-manager.nix and installed by root once.
        # See docs/tailmix-omarchy.md.
        pkgs.tailmix
      ];

      # fu137: Ryzen 9 7950X / RTX 3090 / 30 GiB. Herdr fleet "gpu" worker —
      # users/herdr-fleet.nix keys the workstation-worker role off
      # currentSystemName, so this string is what enrolls the box.
      omarchyHome = mkOmarchyHome {
        hostName = "fu137";
        extraPackages = omarchyExtraPackages;
      };

      # j9: Ryzen 9 9950X3D / RTX 4090 / 60 GiB, a second Omarchy Quattro box,
      # and the Herdr fleet "j9" worker. Distinct from fu137 despite the shared
      # profile, so it needs its own hostName: threading "fu137" through here
      # would hand j9 fu137's identity and its slot in the fleet inventory.
      j9Home = mkOmarchyHome {
        hostName = "j9";
        extraPackages = omarchyExtraPackages;
      };
    in
    {
      # `nix fmt` — formats this repo's own Nix sources only. lib/overlays.nix
      # remains excluded because package-update automation edits its large,
      # mechanically structured blocks in place.
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

      # `nix flake check` — format gate over the repo's own Nix sources, plus an
      # independently schedulable evaluation gate for every host below. Lints
      # (statix/deadnix) live in the devShell but are kept out of checks for now to
      # avoid blocking on pre-existing legacy findings.
      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          inherit (nixpkgs) lib;

          mkHostEvalChecks =
            kind: configs: getDrv:
            lib.mapAttrs' (
              name: cfg:
              lib.nameValuePair "eval-${kind}-${name}" (
                pkgs.runCommandLocal "check-eval-${kind}-${name}"
                  {
                    evaluated = builtins.unsafeDiscardStringContext (getDrv cfg);
                  }
                  ''
                    printf '%s\n' "$evaluated" > $out
                  ''
              )
            ) configs;
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
                  ! -name overlays.nix \
                  -print0 | xargs -0 nixfmt --check; then
                  echo "Nix files are not formatted. Run 'nix fmt' to fix." >&2
                  exit 1
                fi
                touch $out
              '';

          performance-policy =
            pkgs.runCommandLocal "check-nix-performance-policy"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.ripgrep
                ];
              }
              ''
                bash ${./tests/nix-performance-policy.sh} ${self}
                touch $out
              '';
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") (
          # Keep explicit full-module evaluation coverage, but expose each host
          # independently so Determinate Nix can schedule them in parallel.
          mkHostEvalChecks "nixos" (removeAttrs self.nixosConfigurations knownBrokenHosts) (
            cfg: cfg.config.system.build.toplevel.drvPath
          )
          // mkHostEvalChecks "darwin" self.darwinConfigurations (
            cfg: cfg.config.system.build.toplevel.drvPath
          )
          // mkHostEvalChecks "home" self.homeConfigurations (cfg: cfg.activationPackage.drvPath)
        )
      );

      # vm-aarch64, vm-aarch64-utm and vm-aarch64-prl retired 2026-07-28. The
      # Apple-Silicon NixOS VMs were unused and no longer evaluated: 13 tools in
      # lib/overlays.nix ship no aarch64-linux binary. vm-intel remains.

      nixosConfigurations.vm-intel = mkSystem "vm-intel" {
        system = "x86_64-linux";
        user = "joost";
      };

      nixosConfigurations.wsl = mkSystem "wsl" {
        system = "x86_64-linux";
        user = "joost";
        wsl = true;
      };

      nixosConfigurations.fumusic = mkSystem "fumusic" {
        system = "x86_64-linux";
        user = "joost";
      };

      nixosConfigurations.fu095 = mkSystem "fu095" {
        system = "x86_64-linux";
        user = "joost";
      };

      nixosConfigurations.j7 = mkSystem "j7" {
        system = "x86_64-linux";
        user = "joost";
        raphael = true;
        pstate = true;
        zenpower = true;
      };

      # fu137 runs Arch Linux (Omarchy) and is managed entirely through
      # homeConfigurations."fu137" below. Its NixOS output, hosts/fu137.nix,
      # hosts/hardware/fu137.nix and modules/nvidia-drivers-535.nix were
      # removed on 2026-08-30; nothing built them. Recover from git history if
      # the box is ever reinstalled with NixOS.

      nixosConfigurations.github-runner = mkSystem "github-runner" {
        system = "x86_64-linux";
        user = "joost";
      };

      nixosConfigurations.github-runner-03 = mkServer "github-runner-03" "github-runner";
      nixosConfigurations.github-runner-04 = mkServer "github-runner-04" "github-runner";
      nixosConfigurations.github-runner-05 = mkServer "github-runner-05" "github-runner";

      # github-runner-06 removed 2026-07-20 — its EX63 box was wiped and
      # repurposed as bali (loom's replacement).

      # Agent dev box running rondo (autonomous Claude Code agent). Reuses the
      # decommissioned github-runner-01 box. See modules/agent-dev-box.nix and
      # users/agent-jay/ — both designed to scale to more jay machines and new
      # agent users.
      nixosConfigurations.agent-jay-01 = mkServer "agent-jay-01" "agent-jay";

      nixosConfigurations.loom = mkServer "loom" "joost";

      # loom's replacement on a repurposed EX63 runner box (donor: one of
      # github-runner-03..06). Loom stays up until bali is verified;
      # hermes stays disabled on bali until cutover (hosts/bali.nix).
      nixosConfigurations.bali = mkServer "bali" "joost";

      # FashionUnited company-wide hermes-agent host.
      # Clone of loom's hermes-agent setup; see Plans/check-the-plan-for-misty-turtle.md.
      nixosConfigurations.hermes-fu = mkServer "hermes-fu" "agent";

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

      # Home Manager configuration for a GitHub runner on Ubuntu (standalone HM,
      # not NixOS). Its profile lives in users/ubuntu-runner/ — deliberately not
      # users/github-runner/, which is the NixOS runner hosts' user. The attribute
      # name and the `githubrunner` account name are unchanged: both are external
      # contracts (the account exists on that box).
      homeConfigurations."githubrunner" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = overlays;
          # claude-code and cursor-cli (users/agent-clis.nix) are unfree; the
          # NixOS/Darwin hosts get this from lib/mksystem.nix, this standalone
          # profile has to set it itself.
          config.allowUnfree = true;
        };
        modules = [
          ./users/ubuntu-runner/home-manager.nix
          # Same agent CLI toolset the NixOS/Darwin hosts get from
          # lib/mksystem.nix; this profile has no system layer to inherit it.
          ./users/agent-clis.nix
          # mise (dev tool / runtime version manager) and mosh on every machine.
          # Standalone HM on Ubuntu: no system layer, so mosh ships here rather
          # than via lib/mksystem.nix like the NixOS/Darwin hosts.
          (
            { pkgs, ... }:
            {
              home.packages = [
                pkgs.mise
                pkgs.mosh
              ];
            }
          )
        ];
      };

      # Omarchy Quattro package manifests live in /usr/share/omarchy/install.
      # gum, tldr, mpv, localsend, inxi and mise are Quattro core packages, so
      # they stay out of the Nix layer. Two real Omarchy hosts, fu137 and j9;
      # "omarchy" stays an alias for fu137 for older commands.
      homeConfigurations."fu137" = omarchyHome;
      homeConfigurations."j9" = j9Home;
      homeConfigurations."omarchy" = omarchyHome;
    };
}
