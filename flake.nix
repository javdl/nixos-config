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

          # beads_rust (br) - fast Rust port of beads issue tracker
          brVersion = "0.1.14";
          brSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-v${brVersion}-linux_amd64.tar.gz";
              sha256 = "c4f4772032868d0ae2e04e4a13629951c05f14f09ba791ff70e1615cd8ebab1b";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-v${brVersion}-linux_arm64.tar.gz";
              sha256 = "be83abc260f19614b49095e57fd639b0d821115ae22b2b0ba244db0ce193c200";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-v${brVersion}-darwin_amd64.tar.gz";
              sha256 = "cbc3e8baaec46ac1530acaa617e353e944278428e63767e3bff6da7ca04bd757";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-v${brVersion}-darwin_arm64.tar.gz";
              sha256 = "d4826b0f752fa9693607c8d3f09579a0416b95313d0878b49caab243b37b2db2";
            };
          };
          brSource = brSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for br: ${prev.stdenv.hostPlatform.system}");

          # ntm - Named Tmux Manager for AI coding agent coordination
          ntmVersion = "1.7.0";
          ntmSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_linux_amd64.tar.gz";
              sha256 = "045883d4a60b9dd4e1e682f70df732544cf272fa6913918b2f734e088bb776f7";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_linux_arm64.tar.gz";
              sha256 = "874a72742ddc5aef876745dfb6ad322ab70c6427d5f94a265c15f6c5f3e24806";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_darwin_all.tar.gz";
              sha256 = "89bcebbd47b41b9fcae03ed3d1884bedd5c7911518682b6153ff928bf2f61263";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_darwin_all.tar.gz";
              sha256 = "89bcebbd47b41b9fcae03ed3d1884bedd5c7911518682b6153ff928bf2f61263";
            };
          };
          ntmSource = ntmSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for ntm: ${prev.stdenv.hostPlatform.system}");

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

          # caam - coding agent account manager (instant auth switching)
          caamVersion = "0.1.10";
          caamSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_linux_amd64.tar.gz";
              sha256 = "e84fa14fbed25fce02aa7a52c981a795ca424b06c3d73b616e30e6e712fa70c2";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_linux_arm64.tar.gz";
              sha256 = "093fe1e648eb09f9350d422496a575868c5d8b0d065fe4df8185a248df10883a";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_darwin_amd64.tar.gz";
              sha256 = "06b1541607955c1cb4e8c83b006538f8055afdd7d6186fe5548ec5cf10641305";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_darwin_arm64.tar.gz";
              sha256 = "386cf861872740611d42eba14b41cfe526a261552b6ae86e0d9095c635f2f519";
            };
          };
          caamSource = caamSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for caam: ${prev.stdenv.hostPlatform.system}");

          # agent-browser - browser automation CLI for AI agents
          agentBrowserVersion = "0.13.0";
          agentBrowserSources = {
            "x86_64-linux" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-linux-x64";
              sha256 = "a34421a9f7c3e498ce30f6dec4780e53488de5e01f330f2f2abcf8e79a6955f4";
            };
            "aarch64-linux" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-linux-arm64";
              sha256 = "ddc1475a999d1025a7460e7acc71b707d7dd8980345426484c2f5dfc4fb9e79b";
            };
            "x86_64-darwin" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-darwin-x64";
              sha256 = "38058f359f3062394141efacdca6ce81828710032703b4abce5216794d338af5";
            };
            "aarch64-darwin" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-darwin-arm64";
              sha256 = "644ed3755af53e687736854854a5dd10bfb14328643684d019024098c44d684d";
            };
          };
          agentBrowserSource = agentBrowserSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for agent-browser: ${prev.stdenv.hostPlatform.system}");
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
          cass = prev.rustPlatform.buildRustPackage {
            pname = "cass";
            version = cassVersion;

            src = prev.fetchFromGitHub {
              owner = "Dicklesworthstone";
              repo = "coding_agent_session_search";
              rev = "v${cassVersion}";
              hash = "sha256-G7u+61DGssgQEhh8OFlRerR30VwmTqWpskH5HLafPks=";
            };

            cargoLock = {
              lockFile = prev.fetchurl {
                url = "https://github.com/Dicklesworthstone/coding_agent_session_search/raw/v${cassVersion}/Cargo.lock";
                hash = "sha256-OSmZq7uW9bNGOwJWHsBv9yweDs7He7HfIQuRGqxyNBE=";
              };
              outputHashes = {
                "toon_rust-0.1.1" = "sha256-RRYl5AqH0cL01wdwIsc+1E5sevjaK5CukXyUVP3zHV0=";
              };
            };

            nativeBuildInputs = with prev; [
              pkg-config
              cmake
              lld
            ];

            buildInputs = with prev; [
              openssl
              onnxruntime
              libssh2
            ];

            # Point ort-sys to system ONNX Runtime instead of downloading
            ORT_LIB_LOCATION = "${prev.onnxruntime}/lib";
            ORT_PREFER_DYNAMIC_LINK = "1";

            # Skip benchmarks and integration tests
            doCheck = false;

            meta = with prev.lib; {
              description = "Cross-agent session search - index and search AI coding agent conversations";
              homepage = "https://github.com/Dicklesworthstone/coding_agent_session_search";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # br - beads_rust, fast Rust port of beads issue tracker
          beads-rust = prev.stdenv.mkDerivation {
            pname = "beads-rust";
            version = brVersion;

            src = prev.fetchurl {
              url = brSource.url;
              sha256 = brSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.gnutar ];

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp br $out/bin/
              chmod +x $out/bin/br
            '';

            meta = with prev.lib; {
              description = "Fast Rust port of beads issue tracker with SQLite backend";
              homepage = "https://github.com/Dicklesworthstone/beads_rust";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # ntm - Named Tmux Manager for AI coding agent coordination
          ntm = prev.stdenv.mkDerivation {
            pname = "ntm";
            version = ntmVersion;

            src = prev.fetchurl {
              url = ntmSource.url;
              sha256 = ntmSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.gnutar ];

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp ntm $out/bin/
              chmod +x $out/bin/ntm
            '';

            meta = with prev.lib; {
              description = "Named Tmux Manager for spawning and coordinating AI coding agents";
              homepage = "https://github.com/Dicklesworthstone/ntm";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

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

          # caam - coding agent account manager (instant auth switching for AI coding subscriptions)
          caam = prev.stdenv.mkDerivation {
            pname = "caam";
            version = caamVersion;

            src = prev.fetchurl {
              url = caamSource.url;
              sha256 = caamSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.gnutar ];

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp caam $out/bin/
              chmod +x $out/bin/caam
            '';

            meta = with prev.lib; {
              description = "Instant auth switching for AI coding tool subscriptions";
              homepage = "https://github.com/Dicklesworthstone/coding_agent_account_manager";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # caut - coding agent usage tracker
          # No binary releases; requires Rust nightly. Install via: cargo install --git https://github.com/Dicklesworthstone/coding_agent_usage_tracker
          caut = null;

          # frankenterm (ft) - swarm-native terminal for AI agent orchestration
          # Cannot build from source: Cargo.lock has local git path deps (file:///dp/frankensearch)
          # Install via: cargo install --git https://github.com/Dicklesworthstone/frankenterm ft
          frankenterm = null;

          # frankensqlite - Rust reimplementation of SQLite with concurrent writers
          # Cannot build: requires Rust nightly (#![feature(unix_socket_ancillary_data)])
          # Install via: cargo +nightly install --git https://github.com/Dicklesworthstone/frankensqlite
          frankensqlite = null;

          # frankentui (ftui) - minimal TUI kernel for flicker-free terminal UIs
          # Cannot build from source: no Cargo.lock in repo
          # Install via: git clone https://github.com/Dicklesworthstone/frankentui && cd frankentui && cargo run -p ftui-demo-showcase
          frankentui = null;

          # agent-browser - browser automation CLI for AI agents (Rust CLI + Node.js Playwright daemon)
          agent-browser = prev.stdenv.mkDerivation {
            pname = "agent-browser";
            version = agentBrowserVersion;

            src = prev.fetchurl {
              url = agentBrowserSource.url;
              sha256 = agentBrowserSource.sha256;
            };

            dontUnpack = true;

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/agent-browser
              chmod +x $out/bin/agent-browser
            '';

            meta = with prev.lib; {
              description = "Browser automation CLI for AI agents with compact text output";
              homepage = "https://agent-browser.dev";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # codex - OpenAI coding agent CLI (pre-built binary from npm)
          codex = let
            codexVersion = "0.104.0";
            codexSources = {
              "x86_64-linux" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-linux-x64.tgz";
                hash = "sha256-eQjShAeqYq6tmY15Kek1In55pEJdymaAKZ3im6+B3gs=";
                vendorDir = "x86_64-unknown-linux-musl";
              };
              "aarch64-linux" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-linux-arm64.tgz";
                hash = "sha256-Fv+XpFkB+UIhKCKZRpsZbIwyMPBZbmgE/nqW9R5Nn2U=";
                vendorDir = "aarch64-unknown-linux-musl";
              };
              "x86_64-darwin" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-darwin-x64.tgz";
                hash = "sha256-nBkMqrQt8DohSpHLQsVMNab8u+L5SKzF9OO0rRGelfo=";
                vendorDir = "x86_64-apple-darwin";
              };
              "aarch64-darwin" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-darwin-arm64.tgz";
                hash = "sha256-To6PtJom3t1K5E8sG1duBRuau8YCjaoqTYItZIZMbUE=";
                vendorDir = "aarch64-apple-darwin";
              };
            };
            system = prev.stdenv.hostPlatform.system;
            source = codexSources.${system};
          in prev.stdenv.mkDerivation {
            pname = "codex";
            version = codexVersion;

            src = prev.fetchurl {
              url = source.url;
              hash = source.hash;
            };

            sourceRoot = ".";

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp package/vendor/${source.vendorDir}/codex/codex $out/bin/codex
              chmod +x $out/bin/codex
            '';

            meta = with prev.lib; {
              description = "OpenAI Codex CLI coding agent";
              homepage = "https://github.com/openai/codex";
              license = licenses.asl20;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # gemini-cli - Google Gemini coding agent CLI (pre-built JS bundle)
          gemini-cli = prev.stdenv.mkDerivation {
            pname = "gemini-cli";
            version = "0.29.5";

            src = prev.fetchurl {
              url = "https://github.com/google-gemini/gemini-cli/releases/download/v0.29.5/gemini.js";
              hash = "sha256-Yzqi2l41XLNMGNqeVGru0SALc1ZVa2LS4Qk2QiiSasY=";
            };

            dontUnpack = true;

            nativeBuildInputs = [ prev.makeWrapper ];

            installPhase = ''
              mkdir -p $out/lib $out/bin
              cp $src $out/lib/gemini.js
              makeWrapper ${prev.nodejs}/bin/node $out/bin/gemini \
                --add-flags "$out/lib/gemini.js"
            '';

            meta = with prev.lib; {
              description = "Google Gemini CLI coding agent";
              homepage = "https://github.com/google-gemini/gemini-cli";
              license = licenses.asl20;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

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
