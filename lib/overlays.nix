{ inputs }:
let
  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  # Import unstable once per platform for the entire flake evaluation. Keeping
  # this outside the overlay callback lets every host on a platform share it.
  pkgsUnstableForSystem = inputs.nixpkgs.lib.genAttrs supportedSystems (
    system:
    import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
      overlays = [ ];
    }
  );
in
[
      # inputs.jujutsu.overlays.default
      # inputs.zig.overlays.default

      (final: prev:
        let
          pkgs-unstable =
            pkgsUnstableForSystem.${prev.stdenv.hostPlatform.system}
              or (throw "Unsupported system for unstable packages: ${prev.stdenv.hostPlatform.system}");

          # grepai - semantic code search CLI tool
          grepaiVersion = "0.37.0";
          grepaiSources = {
            "x86_64-linux" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_linux_amd64.tar.gz";
              sha256 = "1y36ci4axwvdw77aw52nghp8iiaas5lp5nfkw7hpqpyl76wjz1pl";
            };
            "aarch64-linux" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_linux_arm64.tar.gz";
              sha256 = "0f2lza1b9msycp1893cd8yp6hb9jz4a3x9zwvccjyylp783icnym";
            };
            "x86_64-darwin" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_darwin_amd64.tar.gz";
              sha256 = "1zfclz5lwasgb5xbyc82a8s3xmv7ihp5z5nlgips2g46vbyl4azf";
            };
            "aarch64-darwin" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_darwin_arm64.tar.gz";
              sha256 = "09rlsymy14rx1mhy214d7n2jjzc8gh9rkihikwr6acliz1qxg9vw";
            };
          };
          grepaiSource = grepaiSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for grepai: ${prev.stdenv.hostPlatform.system}");

          # grok - xAI Grok Build CLI (coding agent harness + TUI)
          # Bare static-PIE binary; runs on NixOS with no patchelf needed (verified).
          # Version endpoint: https://x.ai/cli/stable
          grokVersion = "1.0.50";
          grokSources = {
            "x86_64-linux" = {
              url = "https://x.ai/cli/grok-${grokVersion}-linux-x86_64";
              sha256 = "1m94sxyszsqc7bm3sr5jc8nbs2id5w87p213ascjvzq6away03f8";
            };
            "aarch64-linux" = {
              url = "https://x.ai/cli/grok-${grokVersion}-linux-aarch64";
              sha256 = "1h7c712gvhzg8iwszcp5kq7d68md1lpd4lfng03y14r3wmiylzll";
            };
            "x86_64-darwin" = {
              url = "https://x.ai/cli/grok-${grokVersion}-macos-x86_64";
              sha256 = "0an6lp5wr0q71bwp0n5nziksn6vm4fa82par4z3cv19dv89bkwjz";
            };
            "aarch64-darwin" = {
              url = "https://x.ai/cli/grok-${grokVersion}-macos-aarch64";
              sha256 = "1rlnaqs6309y1fx4czbkapiaphnlf38dk6k8k9jgy5j1bpbb2hdg";
            };
          };
          grokSource = grokSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for grok: ${prev.stdenv.hostPlatform.system}");

          # herdr - terminal workspace manager / multiplexer for AI coding agents
          # Bare static-PIE binary (verified `file`: static-pie linked), so it
          # runs on NixOS without patchelf, same as grok above.
          herdrVersion = "0.9.3";
          herdrSources = {
            "x86_64-linux" = {
              url = "https://github.com/herdrdev/herdr/releases/download/v${herdrVersion}/herdr-linux-x86_64";
              sha256 = "19yvyj3l0gqrisknzx3cy3313nfgl7g5chrlhic4iyn2y5jxra0q";
            };
            "aarch64-linux" = {
              url = "https://github.com/herdrdev/herdr/releases/download/v${herdrVersion}/herdr-linux-aarch64";
              sha256 = "1h7mw4qy4dwqamg3q2pqy2hvr8daqbvn9pk057li52374lzamrsd";
            };
            "x86_64-darwin" = {
              url = "https://github.com/herdrdev/herdr/releases/download/v${herdrVersion}/herdr-macos-x86_64";
              sha256 = "0m20blhkyy2nsnf30c0qby8f6syj1158kccng842p0ryzx4daqnv";
            };
            "aarch64-darwin" = {
              url = "https://github.com/herdrdev/herdr/releases/download/v${herdrVersion}/herdr-macos-aarch64";
              sha256 = "0ms1i2i1s8z3giy6g8z1z0iksz4z6bkdb9dzgsmx3ma2mvha6wsi";
            };
          };
          herdrSource = herdrSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for herdr: ${prev.stdenv.hostPlatform.system}");

          # posthog-cli - PostHog CLI (API/MCP tool catalog, source maps, tasks).
          # Linux uses the musl tarballs (verified `file`: static-pie linked), so
          # no patchelf. The tarball ships lib/posthog-api-cli.mjs next to the
          # binary for `posthog-cli api`; keep the layout and put node on PATH.
          posthogCliVersion = "0.18.10";
          posthogCliSources = {
            "x86_64-linux" = {
              target = "x86_64-unknown-linux-musl";
              sha256 = "d4507f08a29e8e89e79c3430841f9da5e2216983e231c219f30c69f4c7ac8c97";
            };
            "aarch64-linux" = {
              target = "aarch64-unknown-linux-musl";
              sha256 = "5b0b26378a3edc4b2de0250c924606f559cfba4f5f2898d8e89b76c8624f1863";
            };
            "x86_64-darwin" = {
              target = "x86_64-apple-darwin";
              sha256 = "31340b1936e36e93fbb6759a506f9cf2b55057bcdf5d18113d67f90d9ebe7e58";
            };
            "aarch64-darwin" = {
              target = "aarch64-apple-darwin";
              sha256 = "ac3610273be3c7bfd31b0e7f81d8b35119543bf66b99f669d1ec50abbb36d0da";
            };
          };
          posthogCliSource = posthogCliSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for posthog-cli: ${prev.stdenv.hostPlatform.system}");

          # moshi-hook - daemon + CLI for the Moshi mobile app (Easy Pair SSH/mosh,
          # agent hooks, approval round-trips). Statically linked Go binary
          # (verified `file`: statically linked), so no patchelf on NixOS.
          # Version endpoint: https://cdn.getmoshi.app/hook/latest/version.txt
          # Checksums: https://cdn.getmoshi.app/hook/<version>/checksums.txt
          moshiHookVersion = "0.4.22";
          moshiHookSources = {
            "x86_64-linux" = {
              url = "https://cdn.getmoshi.app/hook/v${moshiHookVersion}/moshi-hook_Linux_x86_64.tar.gz";
              sha256 = "03jy5ibf79k527wcjnsk6cgnsd2qvdwmmgzh497qzkln32xildq2";
            };
            "aarch64-linux" = {
              url = "https://cdn.getmoshi.app/hook/v${moshiHookVersion}/moshi-hook_Linux_arm64.tar.gz";
              sha256 = "0zkzqjb538hld77if15q1c4353nyk4sxzghijflwn8wmwd6j7v9m";
            };
            "x86_64-darwin" = {
              url = "https://cdn.getmoshi.app/hook/v${moshiHookVersion}/moshi-hook_Darwin_x86_64.tar.gz";
              sha256 = "1k8s7jnlzqzazxl2zf203m0xim1d8jhv0c5x88mzzfpx65rip6i5";
            };
            "aarch64-darwin" = {
              url = "https://cdn.getmoshi.app/hook/v${moshiHookVersion}/moshi-hook_Darwin_arm64.tar.gz";
              sha256 = "1qkx6i0sg6l31zlizxw2ynmm1m2d5q1z34507d59ixf6cka7prfd";
            };
          };
          moshiHookSource = moshiHookSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for moshi-hook: ${prev.stdenv.hostPlatform.system}");

          # tailmix - joins several tailnets at once by running one tsnet client
          # per tailnet behind a single TUN, remapping peers into a local IPv4
          # range and answering MagicDNS with those addresses. Used on bali to
          # reach personal-tailnet machines; node sharing cannot do this because
          # bali is a tagged device and tagged machines cannot accept shares.
          tailmixVersion = "0.1.15";
          tailmixSources = {
            "x86_64-linux" = {
              url = "https://github.com/maisem/tailmix/releases/download/v${tailmixVersion}/tailmix_linux_amd64.tar.gz";
              sha256 = "1a8haz4qyvncpk3db7jja4c6979fkrszb7zsp8p7xihry04igv1c";
            };
            "aarch64-linux" = {
              url = "https://github.com/maisem/tailmix/releases/download/v${tailmixVersion}/tailmix_linux_arm64.tar.gz";
              sha256 = "081xl3zrk7xy1pcmkqqk77pi5ywrq1hkc035z6hsflrw7gqsgpfj";
            };
            "x86_64-darwin" = {
              url = "https://github.com/maisem/tailmix/releases/download/v${tailmixVersion}/tailmix_darwin_amd64.tar.gz";
              sha256 = "18627pwvfpyhzp99yw3zrfccwpwxn3625dvgwkx1v3aagls5z501";
            };
            "aarch64-darwin" = {
              url = "https://github.com/maisem/tailmix/releases/download/v${tailmixVersion}/tailmix_darwin_arm64.tar.gz";
              sha256 = "0lsz5qhbnb7rv442989nb7ndxw08qw2b2a7p8ig08fvg9a42g8mq";
            };
          };
          tailmixSource = tailmixSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for tailmix: ${prev.stdenv.hostPlatform.system}");

          # beads_viewer (bv) - TUI for beads issue tracking
          bvVersion = "0.25.2";
          bvSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_linux_amd64.tar.gz";
              sha256 = "16g1n5hc4f0c0c17nvfj4hv1dc3xvx6cn2anhbvdw3bsmy3r09jc";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_linux_arm64.tar.gz";
              sha256 = "03mfyfv381xxnc2w03q8nnmjk3zhf8wp4m5rz7jarbaik2w68zx5";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_darwin_amd64.tar.gz";
              sha256 = "0aky4r29gc6xpmmdvl65dv34f87ssb49vndb1nsib1vzkm8ibv3k";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_darwin_arm64.tar.gz";
              sha256 = "0n1asczrjh17kinrmdn0afyas5yvd7gkxcrhmdv1yxcaclgrbswc";
            };
          };
          bvSource = bvSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for bv: ${prev.stdenv.hostPlatform.system}");

          # cass - coding agent session search
          cassVersion = "0.10.0";
          cassSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-linux-amd64.tar.gz";
              sha256 = "10a6dia5n86aycdfh1phkjw1h4hrws9871pqdc22wg02m6lai3k3";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-linux-arm64.tar.gz";
              sha256 = "02dg9d5khqvg52zqvmmcv07ajp5n0hbdlpsyiwn5lpzqw7ki552j";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-darwin-arm64.tar.gz";
              sha256 = "100541lv303j1bn8qshxp82zbhh781gcxnv3mysc6ar5kgajz4hx";
            };
          };
          cassSource = cassSources.${prev.stdenv.hostPlatform.system} or null;

          # slb - Shannon Language Benchmark for LLM evaluation
          slbVersion = "0.5.2";
          slbSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_linux_amd64.tar.gz";
              sha256 = "18ff0daf113d2432538e46f3ad21c41a97c8891966da4febcf18d717a5b826ed";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_linux_arm64.tar.gz";
              sha256 = "ff315e57f1c43ebc1acfb7cc26c1cfe8c6b2157300f77f5478c4c6ce59ba4967";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_darwin_amd64.tar.gz";
              sha256 = "23ae548fc44b8a4df3aa9c0dd72151316443051252152864e18e9c42d20c21bc";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_darwin_arm64.tar.gz";
              sha256 = "e6e425605df4ea01fef10c701a139d282613aab22a3a7f49e8e5eb32d6e2f933";
            };
          };
          slbSource = slbSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for slb: ${prev.stdenv.hostPlatform.system}");

          # csctf - Chat Shared Conversation To File
          csctfVersion = "0.4.6";
          csctfSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/chat_shared_conversation_to_file/releases/download/v${csctfVersion}/csctf-linux-x64";
              sha256 = "9f60035bee944f65e86ee9789d7dca49269af1036c5cf6d6352dfeb6a13b5091";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/chat_shared_conversation_to_file/releases/download/v${csctfVersion}/csctf-linux-arm64";
              sha256 = "88dde8c81e738bec6a9fccd387685366415b254918e4ceb0181a4c1bc05a7566";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/chat_shared_conversation_to_file/releases/download/v${csctfVersion}/csctf-macos-x64";
              sha256 = "54b59297a55be14fe0fef45108ad1b88902fe3717776a2973d75c1e564580fc0";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/chat_shared_conversation_to_file/releases/download/v${csctfVersion}/csctf-macos-arm64";
              sha256 = "8ec85133b495b932c62b82e005f58d8e270650a4ead17811064a966ebff09183";
            };
          };
          csctfSource = csctfSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for csctf: ${prev.stdenv.hostPlatform.system}");

          # brenner - Sydney Brenner research platform CLI
          brennerVersion = "0.4.1";
          brennerSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-linux-x64";
              sha256 = "ca831e88e7572479db587ea9464ab85fd57bcf30aa6898a4792a51cbf85a5f47";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-linux-arm64";
              sha256 = "b97f5d92613b7e065e6dc5b2517a00c64976ac9a3829a7804dca07f4af9938a6";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-darwin-x64";
              sha256 = "6c0549d41cd9fa7a109ba8f0aa136e93a2d04de1f9225c292dd7010d053f7e4f";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-darwin-arm64";
              sha256 = "eb26b67d1354a22512dd9139d22723a3023648ff314b12674527f8a10460bec9";
            };
          };
          brennerSource = brennerSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for brenner: ${prev.stdenv.hostPlatform.system}");

          # toon - Token-Optimized Object Notation converter (JSON <-> TOON)
          toonVersion = "0.2.5";
          toonSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-linux-amd64.tar.xz";
              sha256 = "585dcae65d56a30f93ce06cf4952ce60b94d45a7808a223241eff7bb9100ecc7";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-linux-arm64.tar.xz";
              sha256 = "c593477387d0381ad8cb00aaf3e94dfce7840f515a0e4ae1c064badc0fd182f2";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-darwin-amd64.tar.xz";
              sha256 = "52dea87af5f6665b776eb1ebb302b4c8e896acc653ecdf6fe7400ab71df5b66f";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-darwin-arm64.tar.xz";
              sha256 = "901662e3a07ddb4c31507ad750ddd0ab413e100c980d4ae86f0ecd9c645db49f";
            };
          };
          toonSource = toonSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for toon: ${prev.stdenv.hostPlatform.system}");

          # ms - Meta Skill manager with Thompson sampling optimization
          # ms 0.2.2 stopped publishing an aarch64-unknown-linux-gnu asset;
          # msSource falls back to null and meta-skill guards on it.
          msVersion = "0.2.3";
          msSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/meta_skill/releases/download/v${msVersion}/ms-${msVersion}-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "5b3058a4e98231cd38f903bd3f8da8bdf52d245eed6c4a09a6b32eec9e71c4fe";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/meta_skill/releases/download/v${msVersion}/ms-${msVersion}-aarch64-apple-darwin.tar.gz";
              sha256 = "4b91e220ce1f366a934b0a124f2b33b8b8e3b4bba953c0b4350cf3f14ffa4946";
            };
          };
          msSource = msSources.${prev.stdenv.hostPlatform.system} or null;

          # gws - Google Workspace CLI
          gwsVersion = "0.22.5";
          gwsSources = {
            "x86_64-linux" = {
              url = "https://github.com/googleworkspace/cli/releases/download/v${gwsVersion}/google-workspace-cli-x86_64-unknown-linux-musl.tar.gz";
              sha256 = "0879hyfdm2ngsmwmwq0s8jkg3waa1ndpcpgk9wp8gaxiwkfp7d2d";
              dir = ".";
            };
            "aarch64-linux" = {
              url = "https://github.com/googleworkspace/cli/releases/download/v${gwsVersion}/google-workspace-cli-aarch64-unknown-linux-musl.tar.gz";
              sha256 = "16liz5xpdy2czk655zh5c3k51a0ax7n4f2qkq87b2cj9a9izw077";
              dir = ".";
            };
            "x86_64-darwin" = {
              url = "https://github.com/googleworkspace/cli/releases/download/v${gwsVersion}/google-workspace-cli-x86_64-apple-darwin.tar.gz";
              sha256 = "1cj4cmm4vcdh5hjh2k433z6xqmlcsq6y7qindjibpm042irvvyai";
              dir = ".";
            };
            "aarch64-darwin" = {
              url = "https://github.com/googleworkspace/cli/releases/download/v${gwsVersion}/google-workspace-cli-aarch64-apple-darwin.tar.gz";
              sha256 = "1b3x5xbfv3i45j59hhfpayg3vlgshbqdlc46nk2c5cn9bgyryahx";
              dir = ".";
            };
          };
          gwsSource = gwsSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for gws: ${prev.stdenv.hostPlatform.system}");

          # beads_rust (br) - fast Rust port of beads issue tracker
          brVersion = "0.7.4";
          brSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-linux_amd64.tar.gz";
              sha256 = "0crkvhfvh6nlqxxyshb084la29kbcgl35b970i6rp1d1flqlk7ms";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-linux_arm64.tar.gz";
              sha256 = "1mbvviwka3kp8jc3wkkbwgqf3g56g3biyvz49x9n7rks8kdd37by";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-darwin_amd64.tar.gz";
              sha256 = "0vkfjdqnmkmj9w335d53pvynv33wbk2bhwj73dnsy8a9rwgnkliq";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-darwin_arm64.tar.gz";
              sha256 = "1mzs5x8sijziw5cy2vybjdr3hc67n7iiri90sp821xy036wijxjf";
            };
          };
          brSource = brSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for br: ${prev.stdenv.hostPlatform.system}");

          # ntm - Named Tmux Manager for AI coding agent coordination
          ntmVersion = "1.37.0";
          ntmSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_linux_amd64.tar.gz";
              sha256 = "08hxly1dm62wkb0ci6jdmg7szpg06rz13csg4kl47gdiajxrnkvf";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_linux_arm64.tar.gz";
              sha256 = "1wq136qsh4cxy77milavlq46d8x4sa1dwa6b5imm0pk2ycrjml9x";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_darwin_amd64.tar.gz";
              sha256 = "1rgmpr8m192ca1ab0n9phk2xyn9s3nzpxvmgiz43jh7z10g8f7if";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_darwin_arm64.tar.gz";
              sha256 = "1zh0452xsinw43s4zdswqhsfib3c2qjvb8wb5a8k1yznbzbisycs";
            };
          };
          ntmSource = ntmSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for ntm: ${prev.stdenv.hostPlatform.system}");

          # dcg - destructive command guard
          dcgVersion = "0.15.3";
          dcgSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-x86_64-unknown-linux-musl.tar.xz";
              sha256 = "dc7dcec9679f74ac3e6990959771ca0c84168eba658eff64fe9e63f917a84cc4";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-aarch64-unknown-linux-gnu.tar.xz";
              sha256 = "361765877ef5fc2aa89e3d07b189a4abba4368441125fb5f67b5728d26e5b271";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-x86_64-apple-darwin.tar.xz";
              sha256 = "ec548b61a14c29dd2fc9ae54b1512d99cd3a370911e82639ed1fac71eec91585";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-aarch64-apple-darwin.tar.xz";
              sha256 = "50a1a50762299c7e4b5ebaf3f932f45066c8e7c86a1d5d419b01babd1e2698d7";
            };
          };
          dcgSource = dcgSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for dcg: ${prev.stdenv.hostPlatform.system}");

          # caam - coding agent account manager (instant auth switching)
          caamVersion = "0.1.23";
          caamSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_linux_amd64.tar.gz";
              sha256 = "ec78fb3eee2a6c2b087af4cfb13954c702289888c9e9547927e943465eab21b1";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_linux_arm64.tar.gz";
              sha256 = "eb10fcda4a5b13eb349284990752ebe1e2fbc54a16b91516c8759fa7e488381c";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_darwin_amd64.tar.gz";
              sha256 = "b83f458fd8a2499905ef7301d3e022fcba37dc70315cf3b7f37e25e8b42693da";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_darwin_arm64.tar.gz";
              sha256 = "6c5f7426e8c1f24c3d616fb1e5dfeec5b6b423a352b9135b5ccde9b48cfc22d0";
            };
          };
          caamSource = caamSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for caam: ${prev.stdenv.hostPlatform.system}");

          # agent-browser - browser automation CLI for AI agents
          agentBrowserVersion = "0.38.2";
          agentBrowserSources = {
            "x86_64-linux" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-linux-x64";
              sha256 = "1qf0wwc8zrx1yk6kprr9dwxpb6528nsshgsiy1k4cxyvj98pcjx5";
            };
            "aarch64-linux" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-linux-arm64";
              sha256 = "0h3z3i0lp3sikf35arrlgg17vwnbkasmik7qljxrg16yabch4339";
            };
            "x86_64-darwin" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-darwin-x64";
              sha256 = "1756ijws0cc1iw5n1s557bzhlf5jl2crmwizn45qs63a107b8z3q";
            };
            "aarch64-darwin" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-darwin-arm64";
              sha256 = "1yfbwx143rh5l6ylhjw6i98icl24w57zwbcrf3vfhjyrnmmbhs41";
            };
          };
          agentBrowserSource = agentBrowserSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for agent-browser: ${prev.stdenv.hostPlatform.system}");

          # pi - coding agent CLI (Rust port of Mario Zechner's pi)
          piVersion = "0.7.1";
          piSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/pi_agent_rust/releases/download/v${piVersion}/pi-linux-amd64.tar.xz";
              sha256 = "09wbn59s6kay0jmbgsv9vcpm5rxqn68raivlwivzsgjxzyx26z1m";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/pi_agent_rust/releases/download/v${piVersion}/pi-darwin-arm64.tar.xz";
              sha256 = "12dmpwsncql0z4z8nnqhrcjxbns8rz035g3j2pyizzwmmwca1mz0";
            };
          };
          piSource = piSources.${prev.stdenv.hostPlatform.system} or null;

          # xf - cross-format file converter
          xfVersion = "0.4.2";
          xfSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/xf/releases/download/v${xfVersion}/xf-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "8ace80e620e9f16d4aa3c0ace772825b54d02f2ad32c971b9f7f704690328400";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/xf/releases/download/v${xfVersion}/xf-aarch64-apple-darwin.tar.gz";
              sha256 = "2fa29bd24456d1324a3f435cd4d9b2d2279b58f976e58aae4c6becd137e6e477";
            };
          };
          xfSource = xfSources.${prev.stdenv.hostPlatform.system} or null;

          # mcp-agent-mail - Rust replacement for Python mcp_agent_mail
          mcpAgentMailVersion = "0.3.38";
          mcpAgentMailSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/v${mcpAgentMailVersion}/mcp-agent-mail-x86_64-unknown-linux-gnu.tar.xz";
              sha256 = "0ljdl4rxjdclmsx4bx1yh6zmn922qjfl42ywhlyi349f443fyxmn";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/v${mcpAgentMailVersion}/mcp-agent-mail-aarch64-apple-darwin.tar.xz";
              sha256 = "0nkx8w4509habk7zlc55paqa1akh6x7kz2qzs81iji991lrhdlpd";
            };
          };
          mcpAgentMailSource = mcpAgentMailSources.${prev.stdenv.hostPlatform.system} or null;

          # casr - cross agent session resumer
          casrVersion = "0.4.1";
          casrSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/cross_agent_session_resumer/releases/download/v${casrVersion}/casr-x86_64-unknown-linux-musl.tar.xz";
              sha256 = "616c619f2efacbcc18729ab3d5fbc94135c2cc2844249e4a63164c21ea28972f";
            };
          };
          casrSource = casrSources.${prev.stdenv.hostPlatform.system} or null;

          # s2p - source to prompt TUI (bare binary, no tarball)
          s2pVersion = "0.3.4";
          s2pSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/source_to_prompt_tui/releases/download/v${s2pVersion}/s2p-linux-x64";
              sha256 = "0afnmgl7gwaszl84dhlqyraavwxyrv8jw1jz9avm2qfdr6vpi4qp";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/source_to_prompt_tui/releases/download/v${s2pVersion}/s2p-linux-arm64";
              sha256 = "0kd7k3l2s3zx39wpzryw9cjpi8rkznl1da3r1d308rhh59f957yi";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/source_to_prompt_tui/releases/download/v${s2pVersion}/s2p-macos-x64";
              sha256 = "01khyi94d1fr7bifzv9c5jajpazbz38pdc3mkbq2azw4bd1raz4n";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/source_to_prompt_tui/releases/download/v${s2pVersion}/s2p-macos-arm64";
              sha256 = "1bwh4xhlm9i02gimiyz3pkzi0pvfcclsk20zrl5gv0nmjrv6m0j8";
            };
          };
          s2pSource = s2pSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for s2p: ${prev.stdenv.hostPlatform.system}");

          # omp - oh-my-pi coding agent (fork of pi with LSP/DAP and hashline edits)
          # Bare bun-compiled binary. Unlike grok/herdr these are *dynamically*
          # linked against glibc (verified `file` on omp-linux-x64), so the Linux
          # builds need autoPatchelfHook. Upstream also ships musl variants; the
          # glibc ones are used because autoPatchelfHook handles them natively.
          ompVersion = "18.8.7";
          ompSources = {
            "x86_64-linux" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v${ompVersion}/omp-linux-x64";
              sha256 = "12ls2frzxkw4jld45645425616wr5nm770mdpcdvinxcl0srhzxq";
            };
            "aarch64-linux" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v${ompVersion}/omp-linux-arm64";
              sha256 = "1z5hhrbjqvfwhr30fh6p9jvyi4mqvaxjrb6nxph4rdbwxlq2am68";
            };
            "x86_64-darwin" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v${ompVersion}/omp-darwin-x64";
              sha256 = "019vsmx4r8cmi4gddr25rbh4rdd06bqpss86cw03397lc8yqjy4c";
            };
            "aarch64-darwin" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v${ompVersion}/omp-darwin-arm64";
              sha256 = "057fr9jmdbqw6jfvcgl8cq19765bwcfpgldfs9mlh36axyyjf0ng";
            };
          };
          ompSource = ompSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for omp: ${prev.stdenv.hostPlatform.system}");

          # pt - process triage (intelligent process termination)
          ptVersion = "2.3.0";
          ptSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/process_triage/releases/download/v${ptVersion}/pt-core-linux-x86_64-${ptVersion}.tar.gz";
              sha256 = "02g9fkql05x9p6zjclgrm686gvhy9640izzgcbdcxaklz0jvp2gg";
            };
          };
          ptSource = ptSources.${prev.stdenv.hostPlatform.system} or null;

          # rch - remote compilation helper
          rchVersion = "2.1.16";
          rchSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/remote_compilation_helper/releases/download/v${rchVersion}/rch-v${rchVersion}-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "0m9vil58psgkr2r9jcvj3a7927iq3x3lxy4na1lzrss91vl8ynrw";
            };
          };
          rchSource = rchSources.${prev.stdenv.hostPlatform.system} or null;

          # cua - Cua CLI (sandboxes, Spaces, `cua host`, the cua daemon) and
          # cua-spacesd, the host service that provides Spaces to Cua Bots
          # (modules/cua-spaces-host.nix). Both are glibc-linked Rust binaries.
          # Match the daemon pin in the CLI release's libs/cua-spacesd/VERSION:
          # CLI 0.4.1 pins spacesd 0.5.3.
          cuaVersion = "0.4.1";
          cuaSources = {
            "x86_64-linux" = {
              url = "https://github.com/trycua/cua/releases/download/cua-sdk-v${cuaVersion}/cua-cli-${cuaVersion}-linux-x64.tar.gz";
              sha256 = "1hg3sfxzc79930adx1qr5a23j84xixzq7mf8c6ab8abk3fynhlf3";
            };
            "aarch64-darwin" = {
              url = "https://github.com/trycua/cua/releases/download/cua-sdk-v${cuaVersion}/cua-cli-${cuaVersion}-darwin-arm64.tar.gz";
              sha256 = "0a34f5v8xh1swyzfb55z8v15yxhr6d32si22db0d6zbc4hcc34cl";
            };
          };
          cuaSource = cuaSources.${prev.stdenv.hostPlatform.system} or null;
          cuaSpacesdVersion = "0.5.3";
          cuaSpacesdSources = {
            "x86_64-linux" = {
              url = "https://github.com/trycua/cua/releases/download/cua-spacesd-v${cuaSpacesdVersion}/cua-spacesd-linux-x86_64.tar.gz";
              sha256 = "068blq7vxxk9qma4bljkgc7p4ml1d35938p4z9a8xf61ck9q924w";
            };
          };
          cuaSpacesdSource = cuaSpacesdSources.${prev.stdenv.hostPlatform.system} or null;

          # nvidia-sync - NVIDIA Sync, the desktop client for DGX Spark (SSH
          # tunnels, app launching, Tailscale connections, Cluster Assistant).
          # Linux only: NVIDIA ships it as an Electron .deb in its AI Workbench
          # apt repo; macOS gets the `nvidia-sync` cask (users/joost/darwin.nix).
          # Versions and SHA256s: dists/default/proprietary/binary-{amd64,arm64}/Packages
          # under https://workbench.download.nvidia.com/stable/linux/debian.
          nvidiaSyncVersion = "0.117.3-12";
          nvidiaSyncSources = {
            "x86_64-linux" = {
              arch = "amd64";
              sha256 = "0bx9hqzr9gyp1x6bin9i985bvikll3a84dz181xq54nyal55f9x2";
            };
            "aarch64-linux" = {
              arch = "arm64";
              sha256 = "0h5dszz58855nay2ydz7dhjqvfp60nkirs9yc121pycgzabypymc";
            };
          };
          nvidiaSyncSource = nvidiaSyncSources.${prev.stdenv.hostPlatform.system} or null;

          # nvpair - NVIDIA Personal AI Router (PAIR): routes Ollama/OpenAI
          # requests across paired machines. Electron .deb from GitHub releases;
          # the bundled Go services are static. SHA256s are the release asset
          # digests. See users/nvpair-omarchy.nix and docs/nvpair-omarchy.md.
          nvpairVersion = "1.0.0";
          nvpairSources = {
            "x86_64-linux" = {
              arch = "amd64";
              sha256 = "16g4ija8rcax9rwv0fdfd4f1b1jzq01065qbp0cz75xvmmvfjxqs";
            };
            "aarch64-linux" = {
              arch = "arm64";
              sha256 = "1vnvvnjcq8gsm931br6y6x6j8igcm3pymd86jh8lp9zdb67cx41q";
            };
          };
          nvpairSource = nvpairSources.${prev.stdenv.hostPlatform.system} or null;

          # Libraries the Electron .deb apps above (nvidia-sync, nvpair) link
          # against, and the ones Chromium dlopens at runtime.
          electronDebLibs = with prev; [
            alsa-lib
            at-spi2-atk
            at-spi2-core
            cairo
            cups
            dbus
            expat
            glib
            gtk3
            libdrm
            libgbm
            libnotify
            libsecret
            libuuid
            libxkbcommon
            nspr
            nss
            pango
            libx11
            libxcomposite
            libxdamage
            libxext
            libxfixes
            libxrandr
            libxscrnsaver
            libxtst
            libxcb
            libxshmfence
            stdenv.cc.cc.lib
          ];
          electronDebRuntimeDeps = with prev; [ libGL (lib.getLib systemd) libnotify libsecret ];
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
          # grok-build - xAI Grok Build CLI
          # Overrides the nixpkgs package, which lags badly: nixos-26.05 ships
          # 0.2.93 and nixpkgs-unstable 1.0.0, against 1.0.5 upstream (2026-08-20).
          # Drop this block once nixpkgs catches up.
          grok-build = prev.stdenv.mkDerivation {
            pname = "grok-build";
            version = grokVersion;

            src = prev.fetchurl {
              url = grokSource.url;
              sha256 = grokSource.sha256;
            };

            dontUnpack = true;

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/grok
              chmod +x $out/bin/grok
            '';

            meta = with prev.lib; {
              description = "xAI Grok Build CLI - coding agent harness and TUI";
              homepage = "https://github.com/xai-org/grok-build";
              license = licenses.asl20;
              mainProgram = "grok";
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # herdr - terminal workspace manager for AI coding agents
          herdr = prev.stdenv.mkDerivation {
            pname = "herdr";
            version = herdrVersion;

            src = prev.fetchurl {
              url = herdrSource.url;
              sha256 = herdrSource.sha256;
            };

            dontUnpack = true;

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/herdr
              chmod +x $out/bin/herdr
            '';

            meta = with prev.lib; {
              description = "Terminal workspace manager and multiplexer for AI coding agents";
              homepage = "https://github.com/herdrdev/herdr";
              license = licenses.asl20;
              mainProgram = "herdr";
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          posthog-cli = prev.stdenv.mkDerivation {
            pname = "posthog-cli";
            version = posthogCliVersion;

            src = prev.fetchurl {
              url = "https://github.com/PostHog/posthog/releases/download/posthog-cli/v${posthogCliVersion}/posthog-cli-${posthogCliSource.target}.tar.gz";
              sha256 = posthogCliSource.sha256;
            };

            nativeBuildInputs = [ prev.makeWrapper ];

            installPhase = ''
              mkdir -p $out/libexec/posthog-cli $out/bin
              cp -r posthog-cli lib $out/libexec/posthog-cli/
              # EU Cloud by default; an exported POSTHOG_CLI_HOST still wins.
              makeWrapper $out/libexec/posthog-cli/posthog-cli $out/bin/posthog-cli \
                --set-default POSTHOG_CLI_HOST https://eu.posthog.com \
                --suffix PATH : ${prev.lib.makeBinPath [ prev.nodejs ]}
            '';

            meta = with prev.lib; {
              description = "PostHog CLI: API tools, source map uploads and tasks from the terminal";
              homepage = "https://posthog.com/docs/cli";
              license = licenses.mit;
              mainProgram = "posthog-cli";
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # moshi-hook - Moshi mobile app daemon/CLI. The release tarball has
          # several top-level entries (README.md, docs/, moshi-hook), so
          # sourceRoot must be "." for stdenv's unpackPhase. Upstream's install
          # script also drops a `moshi` alias next to the binary; reproduce it as
          # a symlink so `moshi .` works the same way here.
          moshi-hook = prev.stdenv.mkDerivation {
            pname = "moshi-hook";
            version = moshiHookVersion;

            src = prev.fetchurl {
              url = moshiHookSource.url;
              sha256 = moshiHookSource.sha256;
            };

            sourceRoot = ".";

            installPhase = ''
              mkdir -p $out/bin
              cp moshi-hook $out/bin/moshi-hook
              chmod +x $out/bin/moshi-hook
              ln -s moshi-hook $out/bin/moshi
            '';

            meta = with prev.lib; {
              description = "Daemon and CLI for the Moshi mobile terminal app (Easy Pair, agent hooks)";
              homepage = "https://getmoshi.app";
              license = licenses.unfree;
              mainProgram = "moshi-hook";
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # tailmix - multi-tailnet client. Release tarball holds the bare
          # binary plus docs, hence sourceRoot ".".
          tailmix = prev.stdenv.mkDerivation {
            pname = "tailmix";
            version = tailmixVersion;

            src = prev.fetchurl {
              url = tailmixSource.url;
              sha256 = tailmixSource.sha256;
            };

            sourceRoot = ".";

            installPhase = ''
              mkdir -p $out/bin $out/share/tailmix
              # The release ships the CLI *and* the tailmixd daemon; the daemon
              # is what modules/tailmix.nix runs. Installing only the CLI leaves
              # `tailmix status` failing on a missing tailmixd.sock.
              cp tailmix $out/bin/tailmix
              cp tailmixd $out/bin/tailmixd
              chmod +x $out/bin/tailmix $out/bin/tailmixd
              cp README.md LICENSE $out/share/tailmix/
            '';

            meta = with prev.lib; {
              description = "Connect to multiple tailnets at once behind a single TUN";
              homepage = "https://github.com/maisem/tailmix";
              license = licenses.bsd3;
              mainProgram = "tailmix";
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
          ubs = let
            ubsVersion = "5.4.17";
          in prev.stdenv.mkDerivation {
            pname = "ubs";
            version = ubsVersion;

            # 5.4 ships modules/helpers/ubs_core, a Python package of dozens of
            # files, so fetch the tagged tree rather than pinning files one by one.
            src = prev.fetchFromGitHub {
              owner = "Dicklesworthstone";
              repo = "ultimate_bug_scanner";
              rev = "v${ubsVersion}";
              hash = "sha256-ryDAZImE7KuiP88eDjGPou/70oEta5uEnjeRNf3Zuqw=";
            };

            nativeBuildInputs = [ prev.makeWrapper ];

            installPhase = ''
              # ubs resolves modules/helpers relative to its own path
              # (dirname BASH_SOURCE), so the script and modules/ share a directory.
              mkdir -p $out/bin $out/libexec/ubs

              # Install modules non-executable so patchShebangs leaves them alone;
              # rewritten shebangs would break UBS checksum verification.
              cp -r modules $out/libexec/ubs/modules
              chmod -R u+w $out/libexec/ubs/modules
              find $out/libexec/ubs/modules -type f -exec chmod a-x {} +

              cp ubs $out/libexec/ubs/ubs
              chmod +x $out/libexec/ubs/ubs
              wrapProgram $out/libexec/ubs/ubs \
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

              # UBS checks $1 for subcommands (doctor, sessions) before parsing
              # flags, so --module-dir must come AFTER any subcommand, not before.
              # Skip injecting for 'sessions' mode which doesn't use modules.
              cat > $out/bin/ubs <<'WRAPPER'
              #!/usr/bin/env bash
              if [[ "''${1:-}" == "sessions" || "''${1:-}" == "session-log" ]]; then
                exec "PLACEHOLDER_BIN" "$@"
              else
                exec "PLACEHOLDER_BIN" "$@" --module-dir="PLACEHOLDER_DIR"
              fi
              WRAPPER
              substituteInPlace $out/bin/ubs \
                --replace-quiet "PLACEHOLDER_BIN" "$out/libexec/ubs/ubs" \
                --replace-quiet "PLACEHOLDER_DIR" "$out/libexec/ubs/modules"
              chmod +x $out/bin/ubs
            '';

            # Make modules executable after fixupPhase (patchShebangs) has run,
            # preserving original shebangs so UBS checksum verification passes.
            postFixup = ''
              chmod +x $out/libexec/ubs/modules/ubs-*.sh
            '';

            meta = with prev.lib; {
              description = "AI-native code quality scanner detecting 1000+ bug patterns";
              homepage = "https://github.com/Dicklesworthstone/ultimate_bug_scanner";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # cass - coding agent session search TUI (pre-built binary)
          cass = if cassSource != null then prev.stdenv.mkDerivation {
            pname = "cass";
            version = cassVersion;

            src = prev.fetchurl {
              url = cassSource.url;
              sha256 = cassSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.gnutar ]
              ++ prev.lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];

            buildInputs = prev.lib.optionals prev.stdenv.isLinux (with prev; [
              openssl
              onnxruntime
              stdenv.cc.cc.lib  # libstdc++
            ]);

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp cass $out/bin/
              chmod +x $out/bin/cass
            '';

            meta = with prev.lib; {
              description = "Cross-agent session search - index and search AI coding agent conversations";
              homepage = "https://github.com/Dicklesworthstone/coding_agent_session_search";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
            };
          } else null;

          # slb - Shannon Language Benchmark for LLM evaluation
          slb = prev.stdenv.mkDerivation {
            pname = "slb";
            version = slbVersion;

            src = prev.fetchurl {
              url = slbSource.url;
              sha256 = slbSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.gnutar ];

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp slb $out/bin/
              chmod +x $out/bin/slb
            '';

            meta = with prev.lib; {
              description = "Shannon Language Benchmark - evaluate LLM performance with information-theoretic metrics";
              homepage = "https://github.com/Dicklesworthstone/slb";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # csctf - Chat Shared Conversation To File (bare binary, no tarball)
          csctf = prev.stdenv.mkDerivation {
            pname = "csctf";
            version = csctfVersion;

            src = prev.fetchurl {
              url = csctfSource.url;
              sha256 = csctfSource.sha256;
            };

            dontUnpack = true;

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/csctf
              chmod +x $out/bin/csctf
            '';

            meta = with prev.lib; {
              description = "Convert AI chat share links to clean Markdown and HTML transcripts";
              homepage = "https://github.com/Dicklesworthstone/chat_shared_conversation_to_file";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # brenner - Sydney Brenner research platform CLI (bare binary)
          brenner = prev.stdenv.mkDerivation {
            pname = "brenner";
            version = brennerVersion;

            src = prev.fetchurl {
              url = brennerSource.url;
              sha256 = brennerSource.sha256;
            };

            dontUnpack = true;

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/brenner
              chmod +x $out/bin/brenner
            '';

            meta = with prev.lib; {
              description = "Sydney Brenner research platform CLI for AI-assisted scientific inquiry";
              homepage = "https://github.com/Dicklesworthstone/brenner_bot";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # toon - Token-Optimized Object Notation converter
          toon = prev.stdenv.mkDerivation {
            pname = "toon";
            version = toonVersion;

            src = prev.fetchurl {
              url = toonSource.url;
              sha256 = toonSource.sha256;
            };

            sourceRoot = ".";

            unpackPhase = ''
              ${prev.xz}/bin/xz -d < $src | tar xf -
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp toon $out/bin/
              chmod +x $out/bin/toon
            '';

            meta = with prev.lib; {
              description = "Token-Optimized Object Notation - convert between JSON and TOON formats";
              homepage = "https://github.com/Dicklesworthstone/toon_rust";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # ms - Meta Skill manager with Thompson sampling
          meta-skill = if msSource != null then prev.stdenv.mkDerivation {
            pname = "meta-skill";
            version = msVersion;

            src = prev.fetchurl {
              url = msSource.url;
              sha256 = msSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.gnutar ]
              ++ prev.lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];

            buildInputs = prev.lib.optionals prev.stdenv.isLinux (with prev; [
              openssl
              zlib
              stdenv.cc.cc.lib
            ]);

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp ms $out/bin/
              chmod +x $out/bin/ms
            '';

            meta = with prev.lib; {
              description = "Skill management with Thompson sampling optimization";
              homepage = "https://github.com/Dicklesworthstone/meta_skill";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-darwin" ];
            };
          } else null;

          # gws - Google Workspace CLI
          gws = prev.stdenv.mkDerivation {
            pname = "gws";
            version = gwsVersion;

            src = prev.fetchurl {
              url = gwsSource.url;
              sha256 = gwsSource.sha256;
            };

            sourceRoot = gwsSource.dir;

            nativeBuildInputs = [ prev.gnutar ];

            installPhase = ''
              mkdir -p $out/bin
              cp gws $out/bin/
              chmod +x $out/bin/gws
            '';

            meta = with prev.lib; {
              description = "Google Workspace CLI for Drive, Gmail, Calendar, Sheets, Docs, Chat, Admin";
              homepage = "https://github.com/googleworkspace/cli";
              license = licenses.asl20;
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
              ln -s $out/bin/br $out/bin/bd
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
            version = "1.5.0";

            src = prev.fetchurl {
              url = "https://github.com/Dicklesworthstone/repo_updater/releases/download/v1.5.0/ru";
              sha256 = "df405927d525ae6c17cd81365672dbf00c8628f70b7e030476eb55f415541b86";
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

          # cm - cass memory system
          # Pre-built GitHub release binaries are broken (bun cross-compilation doesn't embed scripts).
          # Build from source using bun in a plain derivation with fixed-output hash for deps.
          cass-memory = if prev.stdenv.isLinux && prev.stdenv.hostPlatform.system == "x86_64-linux" then
          let
            src = prev.fetchFromGitHub {
              owner = "Dicklesworthstone";
              repo = "cass_memory_system";
              rev = "v0.2.14";
              hash = "sha256-25NPzERkqZKBwCKf8apcANkV22bNeg0It7E6brtV1aU=";
            };
            # Fixed-output derivation for bun install (needs network)
            bunDeps = prev.stdenv.mkDerivation {
              pname = "cass-memory-bun-deps";
              version = "0.2.14";
              inherit src;
              nativeBuildInputs = [ prev.bun prev.cacert ];
              buildPhase = ''
                export HOME=$TMPDIR
                bun install --frozen-lockfile --ignore-scripts
              '';
              installPhase = ''
                mkdir -p $out
                cp -r node_modules $out/
              '';
              outputHashAlgo = "sha256";
              outputHashMode = "recursive";
              outputHash = "sha256-ToAnXLcbBDzVmLW/ZM0IbHaSPQ80BcVUgu771qPXgcc=";
            };
          in prev.stdenv.mkDerivation {
            pname = "cass-memory";
            version = "0.2.14";
            inherit src;
            nativeBuildInputs = [ prev.bun ];
            # Bun standalone binaries embed JS after the ELF section;
            # strip and patchelf destroy the embedded code.
            dontStrip = true;
            dontPatchELF = true;
            buildPhase = ''
              cp -r ${bunDeps}/node_modules ./node_modules
              bun build src/cm.ts --compile --outfile cm
            '';
            installPhase = ''
              mkdir -p $out/bin
              cp cm $out/bin/cm
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
              cp caam $out/bin/.caam-unwrapped
              chmod +x $out/bin/.caam-unwrapped
              # Wrapper: translate --version to subcommand (ntm health check expects --version)
              cat > $out/bin/caam <<'WRAPPER'
              #!/usr/bin/env bash
              if [[ "$1" == "--version" ]]; then
                exec "$(dirname "$0")/.caam-unwrapped" version
              fi
              exec "$(dirname "$0")/.caam-unwrapped" "$@"
              WRAPPER
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

          # giil - git intelligent issue linker (x86_64-linux only)
          giil = if prev.stdenv.hostPlatform.system == "x86_64-linux" then prev.stdenv.mkDerivation {
            pname = "giil";
            version = "3.2.1";

            src = prev.fetchurl {
              url = "https://github.com/Dicklesworthstone/giil/releases/download/v3.2.1/giil";
              sha256 = "2a1a2b8b658cd2c112406f4fd8943bffb23ba580b736ba0547d7d57703d60bd0";
            };

            dontUnpack = true;

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/giil
              chmod +x $out/bin/giil
            '';

            meta = with prev.lib; {
              description = "Git intelligent issue linker";
              homepage = "https://github.com/Dicklesworthstone/giil";
              license = licenses.mit;
              platforms = [ "x86_64-linux" ];
            };
          } else null;

          # pi - coding agent CLI (Rust port of Mario Zechner's pi)
          pi-agent = if piSource != null then prev.stdenv.mkDerivation {
            pname = "pi-agent";
            version = piVersion;

            src = prev.fetchurl {
              url = piSource.url;
              sha256 = piSource.sha256;
            };

            sourceRoot = ".";

            unpackPhase = ''
              ${prev.xz}/bin/xz -d < $src | tar xf -
            '';

            installPhase = ''
              mkdir -p $out/bin
              # 0.7.1 release archives contain the binary at the root.
              cp pi $out/bin/pi
              chmod +x $out/bin/pi
            '';

            meta = with prev.lib; {
              description = "Coding agent CLI in the terminal (Rust port of pi)";
              homepage = "https://github.com/Dicklesworthstone/pi_agent_rust";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-darwin" ];
            };
          } else null;

          # xf - cross-format file converter
          xf = if xfSource != null then prev.stdenv.mkDerivation {
            pname = "xf";
            version = xfVersion;

            src = prev.fetchurl {
              url = xfSource.url;
              sha256 = xfSource.sha256;
            };

            sourceRoot = ".";

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp xf $out/bin/
              chmod +x $out/bin/xf
            '';

            meta = with prev.lib; {
              description = "Cross-format file converter";
              homepage = "https://github.com/Dicklesworthstone/xf";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          } else null;

          # mcp-agent-mail - Rust replacement for Python mcp_agent_mail
          mcp-agent-mail = if mcpAgentMailSource != null then prev.stdenv.mkDerivation {
            pname = "mcp-agent-mail";
            version = mcpAgentMailVersion;

            src = prev.fetchurl {
              url = mcpAgentMailSource.url;
              sha256 = mcpAgentMailSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = prev.lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];
            buildInputs = prev.lib.optionals prev.stdenv.isLinux [ prev.sqlite prev.zlib prev.stdenv.cc.cc.lib prev.openssl ];

            unpackPhase = ''
              tar xJf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp mcp-agent-mail $out/bin/
              cp am $out/bin/
              chmod +x $out/bin/mcp-agent-mail $out/bin/am
            '';

            meta = with prev.lib; {
              description = "MCP Agent Mail - async multi-agent coordination (Rust)";
              homepage = "https://github.com/Dicklesworthstone/mcp_agent_mail_rust";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-darwin" ];
            };
          } else null;

          # casr - cross agent session resumer
          cross-agent-session-resumer = if casrSource != null then prev.stdenv.mkDerivation {
            pname = "cross-agent-session-resumer";
            version = casrVersion;

            src = prev.fetchurl {
              url = casrSource.url;
              sha256 = casrSource.sha256;
            };

            sourceRoot = ".";

            unpackPhase = ''
              ${prev.xz}/bin/xz -d < $src | tar xf -
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp casr $out/bin/
              chmod +x $out/bin/casr
            '';

            meta = with prev.lib; {
              description = "Cross-agent session resumer for continuing work across AI agents";
              homepage = "https://github.com/Dicklesworthstone/cross_agent_session_resumer";
              license = licenses.mit;
              # 0.2.x ships x86_64-linux only; upstream dropped the darwin asset.
              platforms = [ "x86_64-linux" ];
            };
          } else null;

          # s2p - source to prompt TUI (bare binary)
          s2p = prev.stdenv.mkDerivation {
            pname = "s2p";
            version = s2pVersion;

            src = prev.fetchurl {
              url = s2pSource.url;
              sha256 = s2pSource.sha256;
            };

            dontUnpack = true;

            nativeBuildInputs = prev.lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];
            buildInputs = prev.lib.optionals prev.stdenv.isLinux [ prev.stdenv.cc.cc.lib ];

            installPhase = ''
              mkdir -p $out/bin
              cp $src $out/bin/s2p
              chmod +x $out/bin/s2p
            '';

            meta = with prev.lib; {
              description = "Turn code projects into LLM prompts with a TUI";
              homepage = "https://github.com/Dicklesworthstone/source_to_prompt_tui";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # omp - oh-my-pi coding agent.
          #
          # Do NOT run autoPatchelfHook on this binary. It is a Bun standalone
          # executable: the JS payload is appended past the ELF and located
          # relative to end-of-file, so patchelf's rewrite silently drops it and
          # the result degrades into a plain Bun runtime. Being dynamically
          # linked against glibc does not make the rewrite safe -- that was the
          # reasoning that shipped a patchelf'd build, and the result printed
          # Bun's own "1.4.0" for `omp --version` and Bun's help for
          # `omp --help`. Same class of breakage documented for cm below
          # ("bun cross-compilation doesn't embed scripts").
          #
          # Instead keep the file byte-identical and invoke it through the glibc
          # loader. omp also downloads a pi_natives .node addon into its state
          # dir at runtime and dlopens it, and that addon needs libz, so
          # LD_LIBRARY_PATH has to carry zlib as well as libstdc++.
          omp = prev.stdenv.mkDerivation {
            pname = "omp";
            version = ompVersion;

            src = prev.fetchurl {
              url = ompSource.url;
              sha256 = ompSource.sha256;
            };

            dontUnpack = true;

            nativeBuildInputs = [ prev.makeWrapper ];

            # Stripping would rewrite the ELF the same way patchelf does.
            dontStrip = true;
            dontPatchELF = true;

            installPhase = ''
              mkdir -p $out/bin $out/libexec
              cp $src $out/libexec/omp
              chmod +x $out/libexec/omp
            '' + (if prev.stdenv.hostPlatform.isLinux then ''
              makeWrapper ${prev.stdenv.cc.bintools.dynamicLinker} $out/bin/omp \
                --add-flags $out/libexec/omp \
                --prefix LD_LIBRARY_PATH : ${prev.lib.makeLibraryPath [
                  prev.zlib
                  prev.stdenv.cc.cc.lib
                ]}
            '' else ''
              makeWrapper $out/libexec/omp $out/bin/omp
            '');

            meta = with prev.lib; {
              description = "Coding agent for the terminal with the IDE wired in (oh-my-pi)";
              homepage = "https://github.com/can1357/oh-my-pi";
              license = licenses.mit;
              mainProgram = "omp";
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # hermes - Hermes Agent CLI/TUI (NousResearch), from the flake input.
          # Keep the minimal closure, adding only the native Anthropic transport.
          # Optional SDKs cannot be lazy-installed into the read-only Nix store.
          # The full variant also includes messaging, voice, matrix, bedrock, ...
          # Gateway deployments on bali/hermes-fu use the upstream NixOS module.
          # No x86_64-darwin output upstream; null there and filtered by callers.
          hermes-agent =
            let
              minimal = (inputs.hermes-agent.packages.${prev.stdenv.hostPlatform.system} or { }).minimal or null;
            in
            if minimal == null then null else minimal.override {
              extraDependencyGroups = [ "anthropic" ];
            };

          # pt - process triage (intelligent process termination with Bayesian scoring)
          process-triage = if ptSource != null then prev.stdenv.mkDerivation {
            pname = "process-triage";
            version = ptVersion;

            src = prev.fetchurl {
              url = ptSource.url;
              sha256 = ptSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.gnutar ]
              ++ prev.lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];
            buildInputs = prev.lib.optionals prev.stdenv.isLinux [ prev.stdenv.cc.cc.lib ];

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp pt-core $out/bin/pt
              chmod +x $out/bin/pt
            '';

            meta = with prev.lib; {
              description = "Intelligent process termination with Bayesian scoring";
              homepage = "https://github.com/Dicklesworthstone/process_triage";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          } else null;

          # rch - remote compilation helper
          remote-compilation-helper = if rchSource != null then prev.stdenv.mkDerivation {
            pname = "remote-compilation-helper";
            version = rchVersion;

            src = prev.fetchurl {
              url = rchSource.url;
              sha256 = rchSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.gnutar ]
              ++ prev.lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];
            buildInputs = prev.lib.optionals prev.stdenv.isLinux (with prev; [
              openssl
              stdenv.cc.cc.lib
            ]);

            unpackPhase = ''
              tar xzf $src
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp rch $out/bin/
              cp rchd $out/bin/
              cp rch-wkr $out/bin/
              chmod +x $out/bin/rch $out/bin/rchd $out/bin/rch-wkr
            '';

            meta = with prev.lib; {
              description = "Intercept builds from AI agents and route to remote workers";
              homepage = "https://github.com/Dicklesworthstone/remote_compilation_helper";
              license = licenses.mit;
              platforms = [ "x86_64-linux" ];
            };
          } else null;

          # cua - Cua CLI (see cuaVersion above)
          cua = if cuaSource != null then prev.stdenv.mkDerivation {
            pname = "cua";
            version = cuaVersion;

            src = prev.fetchurl {
              url = cuaSource.url;
              sha256 = cuaSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = prev.lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];
            buildInputs = prev.lib.optionals prev.stdenv.isLinux [ prev.stdenv.cc.cc.lib ];

            installPhase = ''
              install -Dm755 cua $out/bin/cua
            '';

            meta = with prev.lib; {
              description = "Cua CLI: sandboxes, Spaces, unattended hosting and the cua daemon";
              homepage = "https://github.com/trycua/cua";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-darwin" ];
              mainProgram = "cua";
            };
          } else null;

          # cua-spacesd - Cua host service that provides Spaces (see cuaVersion)
          cua-spacesd = if cuaSpacesdSource != null then prev.stdenv.mkDerivation {
            pname = "cua-spacesd";
            version = cuaSpacesdVersion;

            src = prev.fetchurl {
              url = cuaSpacesdSource.url;
              sha256 = cuaSpacesdSource.sha256;
            };

            sourceRoot = ".";

            nativeBuildInputs = [ prev.autoPatchelfHook ];
            buildInputs = with prev; [ stdenv.cc.cc.lib libx11 libxi ];

            installPhase = ''
              install -Dm755 cua-spacesd $out/bin/cua-spacesd
            '';

            meta = with prev.lib; {
              description = "Cua host service: provides Spaces to your devices over the cua.ai relay";
              homepage = "https://github.com/trycua/cua/tree/main/libs/cua-spacesd";
              license = licenses.fsl11Mit;
              platforms = [ "x86_64-linux" ];
              mainProgram = "cua-spacesd";
            };
          } else null;

          # nvidia-sync - NVIDIA Sync desktop client (see nvidiaSyncVersion)
          nvidia-sync = if nvidiaSyncSource != null then prev.stdenv.mkDerivation {
            pname = "nvidia-sync";
            version = nvidiaSyncVersion;

            src = prev.fetchurl {
              url = "https://workbench.download.nvidia.com/stable/linux/debian/pool/proprietary/n/nvidia-sync/nvidia-sync_${nvidiaSyncVersion}_${nvidiaSyncSource.arch}.deb";
              sha256 = nvidiaSyncSource.sha256;
            };

            nativeBuildInputs = with prev; [ dpkg autoPatchelfHook makeWrapper ];

            buildInputs = electronDebLibs;
            runtimeDependencies = electronDebRuntimeDeps;
            dontStrip = true;

            # The nvsync Go helper segfaults (SEGV_ACCERR) once patchelf adds an
            # RPATH, so only the Electron files get autoPatchelf; the helper
            # needs just libc and gets the interpreter alone.
            dontAutoPatchelf = true;
            postFixup = ''
              autoPatchelf --no-recurse -- $out/opt/nvidia-sync
              patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
                $out/opt/nvidia-sync/resources/bin/nvsync-${nvidiaSyncSource.arch}
            '';

            unpackPhase = ''
              dpkg-deb -x $src .
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p $out/opt $out/bin
              cp -r "opt/NVIDIA Sync" $out/opt/nvidia-sync
              # The store is read-only: drop the electron-updater feed so the app
              # does not try to self-update through dpkg.
              rm $out/opt/nvidia-sync/resources/app-update.yml

              # Upstream's launcher script forces X11 (XWayland under Hyprland).
              # ssh/xdg-open are spawned by the app and its nvsync helper.
              makeWrapper $out/opt/nvidia-sync/nvidia-sync.bin $out/bin/nvidia-sync \
                --add-flags --ozone-platform=x11 \
                --suffix PATH : ${prev.lib.makeBinPath [ prev.openssh prev.xdg-utils ]}
              makeWrapper $out/opt/nvidia-sync/resources/bin/nvsync-${nvidiaSyncSource.arch} $out/bin/nvsync \
                --suffix PATH : ${prev.lib.makeBinPath [ prev.openssh ]}

              install -Dm644 usr/share/icons/hicolor/512x512/apps/nvidia-sync.png \
                $out/share/icons/hicolor/512x512/apps/nvidia-sync.png
              install -Dm644 usr/share/applications/nvidia-sync.desktop \
                $out/share/applications/nvidia-sync.desktop
              substituteInPlace $out/share/applications/nvidia-sync.desktop \
                --replace-fail '"/opt/NVIDIA Sync/nvidia-sync" --ozone-platform=x11' "$out/bin/nvidia-sync"

              runHook postInstall
            '';

            meta = with prev.lib; {
              description = "NVIDIA Sync: SSH tunnels and one-click apps on a remote DGX Spark";
              homepage = "https://docs.nvidia.com/sync/latest/index.html";
              license = licenses.unfree;
              sourceProvenance = [ sourceTypes.binaryNativeCode ];
              platforms = [ "x86_64-linux" "aarch64-linux" ];
              mainProgram = "nvidia-sync";
            };
          } else null;

          # nvpair - NVIDIA Personal AI Router (see nvpairVersion)
          nvpair = if nvpairSource != null then prev.stdenv.mkDerivation {
            pname = "nvpair";
            version = nvpairVersion;

            src = prev.fetchurl {
              url = "https://github.com/NVIDIA/Personal-AI-Router/releases/download/v${nvpairVersion}/NVPAIR-Setup-${nvpairVersion}-${nvpairSource.arch}.deb";
              sha256 = nvpairSource.sha256;
            };

            nativeBuildInputs = with prev; [ dpkg autoPatchelfHook makeWrapper ];
            buildInputs = electronDebLibs;
            runtimeDependencies = electronDebRuntimeDeps;
            # resources/cli-bin/manifest.json pins the SHA256 of every static Go
            # service binary; stripping would change them.
            dontStrip = true;

            unpackPhase = ''
              dpkg-deb -x $src .
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p $out/opt $out/bin $out/share
              cp -r opt/PAIR $out/opt/PAIR
              # The store is read-only: no electron-updater feed (it would try
              # to install the next .deb through dpkg). Bump nvpairVersion
              # instead, on every node at once: mixed-version clusters are
              # unsupported upstream.
              rm $out/opt/PAIR/resources/app-update.yml

              # The engine manager installs Ollama with `tar --zstd` and reads
              # GPU telemetry from nvidia-smi; the host PATH comes first so
              # Arch's /usr/bin/nvidia-smi stays in use.
              makeWrapper $out/opt/PAIR/nvpair $out/bin/nvpair-desktop \
                --suffix PATH : ${prev.lib.makeBinPath [ prev.gnutar prev.zstd prev.xdg-utils ]}
              # Upstream's `nvpair` command is the terminal UI.
              ln -s $out/opt/PAIR/resources/cli-bin/nvpair-tui $out/bin/nvpair

              cp -r usr/share/icons $out/share/icons
              install -Dm644 usr/share/applications/nvpair.desktop \
                $out/share/applications/nvpair.desktop
              substituteInPlace $out/share/applications/nvpair.desktop \
                --replace-fail /opt/PAIR/nvpair $out/bin/nvpair-desktop

              runHook postInstall
            '';

            meta = with prev.lib; {
              description = "NVIDIA Personal AI Router: routes local inference across paired machines";
              homepage = "https://github.com/NVIDIA/Personal-AI-Router";
              license = licenses.asl20;
              sourceProvenance = [ sourceTypes.binaryNativeCode ];
              platforms = [ "x86_64-linux" "aarch64-linux" ];
              mainProgram = "nvpair-desktop";
            };
          } else null;

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

          # Unpacked browser extension; load the same stable home path in each
          # Chromium browser. Local patch refreshes the subscription model list.
          sitegeist = prev.stdenvNoCC.mkDerivation {
            pname = "sitegeist";
            version = "1.0.0";
            src = prev.fetchurl {
              url = "https://github.com/badlogic/sitegeist/releases/download/v1.0.0/sitegeist.zip";
              sha256 = "1669gvbrwhs1g6rycp5my8ssiynfghhg1jk86xxyvhi2a2b9rxbn";
            };
            nativeBuildInputs = [ prev.unzip prev.python3 prev.nodejs ];
            sourceRoot = ".";
            postPatch = ''
              python ${./sitegeist-models.py} .
              node --check sidepanel.js
              node --check debug.js
            '';
            installPhase = ''
              mkdir -p $out/share/sitegeist
              cp -r . $out/share/sitegeist/
            '';
            meta = {
              description = "Browser sidebar AI assistant with current Codex models";
              homepage = "https://github.com/badlogic/sitegeist";
              license = prev.lib.licenses.agpl3Only;
              platforms = supportedSystems;
            };
          };

          # Keep nixpkgs' native packaging, wrappers and sandbox dependencies.
          claude-code = prev.claude-code.override {
            manifest = {
              version = "2.1.295";
              platforms = {
                "linux-x64".checksum = "4503bfe11a6c7fcc1e0b39b5e0d347c04248f750b03b0977b3ad6b531fe6f358";
                "linux-arm64".checksum = "cfb9dc1332fb6f92a683f835823e91b3179a803398ca7852cd2381a3cb1dea3b";
                "darwin-x64".checksum = "a6066492288585a1ef5e482cb28ad22714ab12cd48e367c0cee988b00cff724c";
                "darwin-arm64".checksum = "0116ee2e0a513900b633d9951367f18747686478e2b462805b8c31609f047f70";
              };
            };
          };

          # codex - OpenAI coding agent CLI (pre-built binary from npm)
          codex = let
            codexVersion = "0.162.0";
            codexSources = {
              "x86_64-linux" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-linux-x64.tgz";
                hash = "sha256-29NC562JbVPbtQXpJvG4IxS3mp0z4gmwt2Fs7WsGyYM=";
                vendorDir = "x86_64-unknown-linux-musl";
              };
              "aarch64-linux" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-linux-arm64.tgz";
                hash = "sha256-AJYPU0ALCD69KsxFKbLOFtW6+W2ak8NmUFUToe2KpVg=";
                vendorDir = "aarch64-unknown-linux-musl";
              };
              "x86_64-darwin" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-darwin-x64.tgz";
                hash = "sha256-bhWRe+AUX1xjE58YcDqLFt7hBBNRaXVC0P5MgL9Dbm0=";
                vendorDir = "x86_64-apple-darwin";
              };
              "aarch64-darwin" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-darwin-arm64.tgz";
                hash = "sha256-5ifWQDzjG9pX1XYpoAhqVl1fa1exVKupLhydskY4dOs=";
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

            # codex 0.139.0 changed the npm tarball to layoutVersion 1: the binary
            # lives at vendor/<target>/bin/codex and resolves sibling codex-resources/
            # (bundled zsh) and codex-path/ (bundled rg) relative to the real exe path.
            # Install the whole vendor tree and symlink the entrypoint so those resolve.
            installPhase = ''
              mkdir -p $out/bin $out/libexec
              cp -r package/vendor/${source.vendorDir} $out/libexec/codex
              chmod -R u+w $out/libexec/codex
              chmod +x $out/libexec/codex/bin/codex
              ln -s $out/libexec/codex/bin/codex $out/bin/codex
            '';

            meta = with prev.lib; {
              description = "OpenAI Codex CLI coding agent";
              homepage = "https://github.com/openai/codex";
              license = licenses.asl20;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # tokscale - token usage tracker across AI coding agents (pre-built
          # binary from npm). GitHub releases carry no assets; the binaries live
          # in the @tokscale/cli-<platform> npm packages. Linux uses the static
          # musl builds so no patchelf is needed. Hashes are npm's dist.integrity.
          tokscale = let
            tokscaleVersion = "4.18.0";
            tokscaleSources = {
              "x86_64-linux" = {
                platform = "linux-x64-musl";
                hash = "sha512-DLlpSZpTU2cpG5OK4rfErASLCnBMLk5EzCTAfdyFeD3unO80zBDqTyGmQQpJs5Mx1urPHXt30D9mzQIt+6KBnw==";
              };
              "aarch64-linux" = {
                platform = "linux-arm64-musl";
                hash = "sha512-+IISSkQAEF7Eb3wH8WpLdeIX1t7RQ05vedMLMP/caMT2vUNshjwIr4ZKqoTQgivqiKyUfh35q+xm4Gv2g76y9Q==";
              };
              "x86_64-darwin" = {
                platform = "darwin-x64";
                hash = "sha512-eNXeQ47QsAKZUL1bWdRQ5dSSc037jpytTCFnNQP7QTu84QYyPMXtTnKJTBG32l3fezAY6C7uzEnMObYNtPXoyQ==";
              };
              "aarch64-darwin" = {
                platform = "darwin-arm64";
                hash = "sha512-1ILrvDJjLmTs+CZ8EYrzqh74QRAGiKDQmqU8HOo+juZ3wTmL/1B7uFsqBL8/+nv5rJCRq4/V7pvT39ZvauJ37g==";
              };
            };
            source = tokscaleSources.${prev.stdenv.hostPlatform.system};
          in prev.stdenv.mkDerivation {
            pname = "tokscale";
            version = tokscaleVersion;

            src = prev.fetchurl {
              url = "https://registry.npmjs.org/@tokscale/cli-${source.platform}/-/cli-${source.platform}-${tokscaleVersion}.tgz";
              inherit (source) hash;
            };

            sourceRoot = ".";

            unpackPhase = ''
              tar xzf $src
            '';

            # The darwin packages also ship libFoundationModels.dylib next to the
            # binary (loaded at runtime), so copy the whole bin/ directory.
            installPhase = ''
              mkdir -p $out/bin
              cp package/bin/* $out/bin/
              chmod +x $out/bin/tokscale
            '';

            meta = with prev.lib; {
              description = "Track token usage across AI coding agents";
              homepage = "https://github.com/junhoyeo/tokscale";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # gemini-cli - Google Gemini coding agent CLI (pre-built JS bundle)
          gemini-cli = prev.stdenv.mkDerivation {
            pname = "gemini-cli";
            version = "0.63.0";

            src = prev.fetchzip {
              url = "https://github.com/google-gemini/gemini-cli/releases/download/v0.63.0/gemini-cli-bundle.zip";
              hash = "sha256-FSJZrDW553M7kc/b8KuI0I4/tcO6/909d7jNT56ULss=";
              stripRoot = false;
            };

            nativeBuildInputs = [ prev.makeWrapper ];

            installPhase = ''
              mkdir -p $out/lib $out/bin
              cp -r . $out/lib/gemini-cli
              makeWrapper ${prev.nodejs}/bin/node $out/bin/gemini \
                --add-flags "$out/lib/gemini-cli/gemini.js"
            '';

            meta = with prev.lib; {
              description = "Google Gemini CLI coding agent";
              homepage = "https://github.com/google-gemini/gemini-cli";
              license = licenses.asl20;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # grok-bot-cli - CLI for xAI Grok Bot agents and groups (gbot command)
          # npm tarball ships a self-contained rspack bundle with no runtime
          # dependencies; needs node >= 22.19 and the Grok Bot desktop app's
          # signed-in session (grok-bot cask on radon, users/joost/darwin.nix).
          grok-bot-cli = prev.stdenv.mkDerivation rec {
            pname = "grok-bot-cli";
            version = "0.12.4";

            src = prev.fetchurl {
              url = "https://registry.npmjs.org/grok-bot-cli/-/grok-bot-cli-${version}.tgz";
              sha256 = "0mbf5l3cpd8bxq52nmm1rj9z0jjaxj0rgxnpf5l7k27x01aldac0";
            };

            nativeBuildInputs = [ prev.makeWrapper ];

            # Grok Bot desktop >= 0.68 writes gateway-descriptor.json version 3
            # (v2 layout plus savedAtMs), which 0.12.4 rejects with "Unsupported
            # Grok Bot gateway descriptor version 3". Same two-line change as
            # upstream PR #143 (issue #149); drop once a release includes it.
            postPatch = ''
              for f in dist/bin/gbot.mjs dist/bin/gbot-flight.mjs \
                       dist/mcp/mcp-grok-bot-b8c2461e.mjs \
                       dist/mcp/mcp-grok-bot-b8c2461e-flight.mjs \
                       dist/scripts/gbot-relay.mjs; do
                substituteInPlace "$f" \
                  --replace-fail 'wrapped.version !== 1 && wrapped.version !== 2)' \
                                 'wrapped.version !== 1 && wrapped.version !== 2 && wrapped.version !== 3)' \
                  --replace-fail 'if (wrapped.version === 2) {' \
                                 'if (wrapped.version === 2 || wrapped.version === 3) {'
              done
            '';

            installPhase = ''
              mkdir -p $out/lib $out/bin
              cp -r . $out/lib/grok-bot-cli
              makeWrapper ${prev.nodejs}/bin/node $out/bin/gbot \
                --add-flags "$out/lib/grok-bot-cli/dist/bin/gbot.mjs"
              ln -s gbot $out/bin/grok-bot
              makeWrapper ${prev.nodejs}/bin/node $out/bin/gbot-install \
                --add-flags "$out/lib/grok-bot-cli/dist/bin/gbot-install.js"
            '';

            meta = with prev.lib; {
              description = "CLI for xAI Grok Bot agents and groups";
              homepage = "https://github.com/ScriptedAlchemy/grok-bot-cli";
              license = licenses.mit;
              mainProgram = "gbot";
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # cco - Claude Code sandbox (bubblewrap on Linux, sandbox-exec on macOS)
          cco = prev.stdenv.mkDerivation {
            pname = "cco";
            version = "0-unstable-2026-09-01";

            src = prev.fetchFromGitHub {
              owner = "nikvdp";
              repo = "cco";
              rev = "68f92e899738f91a2646674c82c7a44946fcf74d";
              sha256 = "0wqzhk97q0gl2zyj9bc4gvwfdj61l4s8sgndawgp4x4r0y9l0bjl";
            };

            nativeBuildInputs = [ prev.makeWrapper ];

            installPhase = ''
              mkdir -p $out/share/cco $out/bin
              cp -r . $out/share/cco/
              chmod +x $out/share/cco/cco
              makeWrapper $out/share/cco/cco $out/bin/cco \
                --prefix PATH : ${prev.lib.makeBinPath ([
                  prev.bash
                  prev.coreutils
                  prev.git
                  prev.curl
                  prev.docker-client
                ] ++ prev.lib.optionals prev.stdenv.isLinux [ prev.bubblewrap ])}
            '';

            meta = with prev.lib; {
              description = "Sandbox wrapper for Claude Code and other AI coding agents";
              homepage = "https://github.com/nikvdp/cco";
              license = licenses.mit;
              platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
            };
          };

          # LM Studio desktop app (Linux only, macOS uses brew cask)
          lmstudio = if prev.stdenv.isLinux then pkgs-unstable.lmstudio else null;

          # gh CLI on stable has bugs.
          gh = pkgs-unstable.gh;

          # nixos-26.05 macmon is 0.6.1, which panics on startup on
          # aarch64-darwin (NixOS/nixpkgs#562942), so CPU/GPU temperatures
          # never get read. Unstable has 0.8.2.
          macmon = pkgs-unstable.macmon;

          # Want the latest version of these
          nushell = pkgs-unstable.nushell;
          google-cloud-sdk = pkgs-unstable.google-cloud-sdk;

          # direnv 2.37.1 test-fish gets SIGKILLed in the Darwin sandbox; skip tests.
          direnv = prev.direnv.overrideAttrs (_: { doCheck = false; });

          # pipx 1.8.0 tests/test_package_specifier.py expects PEP 508 URL specs
          # without a space ("black@ https://...") but the current `packaging`
          # canonicalizes with a space ("black @ https://..."), so 7 tests fail and
          # the build aborts. The output isn't in any binary cache anymore, so a
          # clean store (the runners) can't build it. Skip that one stale test file.
          pipx = prev.pipx.overridePythonAttrs (old: {
            disabledTestPaths = (old.disabledTestPaths or []) ++ [ "tests/test_package_specifier.py" ];
          });

          # nixpkgs 26.05 wires only the node24 externals into github-runner
          # (Node 20 is EOL). But the runner still uses node20 for its built-in
          # hashFiles() helper (and for node20 JS actions before GitHub's
          # 2026-06-16 cutover), exec'ing lib/externals/node20/bin/node. With
          # node20 absent, any ${{ hashFiles(...) }} expression fails template
          # evaluation with "An error occurred trying to start process
          # .../node20/bin/node ... No such file or directory". The
          # FORCE_JAVASCRIPT_ACTIONS_TO_NODE24 runner env var only covers JS
          # *actions*, not hashFiles. Alias node20 -> node24 so every node20
          # invocation runs on the present node24 (GitHub's 2026-06-16 default).
          github-runner = prev.github-runner.overrideAttrs (old: {
            postFixup = (old.postFixup or "") + ''
              ext="$out/lib/externals"
              if [ -e "$ext/node24" ] && [ ! -e "$ext/node20" ]; then
                ln -s node24 "$ext/node20"
              fi
            '';
          });

        })
]
