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
          grokVersion = "1.0.41";
          grokSources = {
            "x86_64-linux" = {
              url = "https://x.ai/cli/grok-${grokVersion}-linux-x86_64";
              sha256 = "01q4wy1dyvnk13q0gqg3w6cpi8hkc8yjd5j45c3h3shn7v93xq4w";
            };
            "aarch64-linux" = {
              url = "https://x.ai/cli/grok-${grokVersion}-linux-aarch64";
              sha256 = "0x0dwrkf14mhhr5z17rgf9g8q6s76cqdk7pi6wh8x9zn7abqq2vw";
            };
            "x86_64-darwin" = {
              url = "https://x.ai/cli/grok-${grokVersion}-macos-x86_64";
              sha256 = "0nyrh2zyh52bdq880sya02k2myccq8z4p9h5wh2gd81kiymh9klg";
            };
            "aarch64-darwin" = {
              url = "https://x.ai/cli/grok-${grokVersion}-macos-aarch64";
              sha256 = "07ar3jrq2iqiri9m517dw7l4n0lafjrv48mdv63hf6356fqlx14w";
            };
          };
          grokSource = grokSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for grok: ${prev.stdenv.hostPlatform.system}");

          # herdr - terminal workspace manager / multiplexer for AI coding agents
          # Bare static-PIE binary (verified `file`: static-pie linked), so it
          # runs on NixOS without patchelf, same as grok above.
          herdrVersion = "0.9.1";
          herdrSources = {
            "x86_64-linux" = {
              url = "https://github.com/herdrdev/herdr/releases/download/v${herdrVersion}/herdr-linux-x86_64";
              sha256 = "1dslbhymcl24sk93q1ddb3fa8b35iw23zm710vq1wrgbdg8zw0ia";
            };
            "aarch64-linux" = {
              url = "https://github.com/herdrdev/herdr/releases/download/v${herdrVersion}/herdr-linux-aarch64";
              sha256 = "17ldpldp5ayf4qqaipjq5bn51b9xf2irnglqkaivjb2zfkgg9k7l";
            };
            "x86_64-darwin" = {
              url = "https://github.com/herdrdev/herdr/releases/download/v${herdrVersion}/herdr-macos-x86_64";
              sha256 = "150yrqmr3mlbr19k3d55afkzdr2l21jldnzvbsmm9zimk5iy0fq5";
            };
            "aarch64-darwin" = {
              url = "https://github.com/herdrdev/herdr/releases/download/v${herdrVersion}/herdr-macos-aarch64";
              sha256 = "1pl97hqs421drswqb0mbilk5fcv94nqdr2dah3x5djpsmpksgisz";
            };
          };
          herdrSource = herdrSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for herdr: ${prev.stdenv.hostPlatform.system}");

          # moshi-hook - daemon + CLI for the Moshi mobile app (Easy Pair SSH/mosh,
          # agent hooks, approval round-trips). Statically linked Go binary
          # (verified `file`: statically linked), so no patchelf on NixOS.
          # Version endpoint: https://cdn.getmoshi.app/hook/latest/version.txt
          # Checksums: https://cdn.getmoshi.app/hook/<version>/checksums.txt
          moshiHookVersion = "0.3.27";
          moshiHookSources = {
            "x86_64-linux" = {
              url = "https://cdn.getmoshi.app/hook/v${moshiHookVersion}/moshi-hook_Linux_x86_64.tar.gz";
              sha256 = "0lkrfd181ag8larkzsm32bpg0qpddwhpszd1554rdrzn94z83szz";
            };
            "aarch64-linux" = {
              url = "https://cdn.getmoshi.app/hook/v${moshiHookVersion}/moshi-hook_Linux_arm64.tar.gz";
              sha256 = "0jvm6jp42p1c3b7d49fv3kczi551zkf7i3lp9gi3z155rf6awncs";
            };
            "x86_64-darwin" = {
              url = "https://cdn.getmoshi.app/hook/v${moshiHookVersion}/moshi-hook_Darwin_x86_64.tar.gz";
              sha256 = "0gldvfgri26scrbyndx16i55vz3bjl5nn9lijbfsq20dr4ffnp4w";
            };
            "aarch64-darwin" = {
              url = "https://cdn.getmoshi.app/hook/v${moshiHookVersion}/moshi-hook_Darwin_arm64.tar.gz";
              sha256 = "0h9600i6s7bidv1lvgh3ifb0wwa3qzfllzkbmy00fj8ckivraha5";
            };
          };
          moshiHookSource = moshiHookSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for moshi-hook: ${prev.stdenv.hostPlatform.system}");

          # tailmix - joins several tailnets at once by running one tsnet client
          # per tailnet behind a single TUN, remapping peers into a local IPv4
          # range and answering MagicDNS with those addresses. Used on bali to
          # reach personal-tailnet machines; node sharing cannot do this because
          # bali is a tagged device and tagged machines cannot accept shares.
          tailmixVersion = "0.1.12";
          tailmixSources = {
            "x86_64-linux" = {
              url = "https://github.com/maisem/tailmix/releases/download/v${tailmixVersion}/tailmix_linux_amd64.tar.gz";
              sha256 = "02xg6xjqxjwlqx6jlncjn8i35v24avps88kzbc3n1q0w9csx85g3";
            };
            "aarch64-linux" = {
              url = "https://github.com/maisem/tailmix/releases/download/v${tailmixVersion}/tailmix_linux_arm64.tar.gz";
              sha256 = "0j63g7g5rbjk4lg7mbd158kl1ymszigb4lga8f34kxy3vikhd45w";
            };
            "x86_64-darwin" = {
              url = "https://github.com/maisem/tailmix/releases/download/v${tailmixVersion}/tailmix_darwin_amd64.tar.gz";
              sha256 = "1gly332kbhwfra3pa0g98l7n8fqvca4g6sag3cwgq9bhp2b0rdb6";
            };
            "aarch64-darwin" = {
              url = "https://github.com/maisem/tailmix/releases/download/v${tailmixVersion}/tailmix_darwin_arm64.tar.gz";
              sha256 = "0w58awxfi32ysnwphn8zgcy1xy0a6a3njfjdqrsw1gsgznczihl0";
            };
          };
          tailmixSource = tailmixSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for tailmix: ${prev.stdenv.hostPlatform.system}");

          # beads_viewer (bv) - TUI for beads issue tracking
          bvVersion = "0.25.0";
          bvSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_linux_amd64.tar.gz";
              sha256 = "0ab43fjy04isnkigij6pymypbr9nw3bz6b2iicv6cnqnvpx6nxga";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_linux_arm64.tar.gz";
              sha256 = "10g7fr31qvghryshx3gq88w9a3kqkiays659lwc4gfnzvfslssw8";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_darwin_amd64.tar.gz";
              sha256 = "11bz1fpay1rgdzfcad8yncf60z223akyfs7172fl25mrcpzb8zx7";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_darwin_arm64.tar.gz";
              sha256 = "1wa5jy0xnz1x7fncxyj486rqk29mcc80k3cvgspj3svgcg335ldw";
            };
          };
          bvSource = bvSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for bv: ${prev.stdenv.hostPlatform.system}");

          # cass - coding agent session search
          cassVersion = "0.8.0";
          cassSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-linux-amd64.tar.gz";
              sha256 = "0271qbaws0dvjhrgc95fzkf1g4a7x4jmqkf73kyn59v4i3bcn198";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-linux-arm64.tar.gz";
              sha256 = "1xzb3nbrhqhv4g4mhh4q0laj0kkkhmkg6fx0cikvl8922g7hs1v6";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-darwin-arm64.tar.gz";
              sha256 = "0mbb3xis42p9q1vdah8sz8fhpdifdhknlkifny96mzrp9612yxwy";
            };
          };
          cassSource = cassSources.${prev.stdenv.hostPlatform.system} or null;

          # slb - Shannon Language Benchmark for LLM evaluation
          slbVersion = "0.4.1";
          slbSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_linux_amd64.tar.gz";
              sha256 = "9c398fb7f8d3bdaca8ad4e70497e84451609993eb5ba4e9b7cea52a8a7247972";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_linux_arm64.tar.gz";
              sha256 = "e689a8bd32c63dbbd01c02e8e63bcdb4264b33d57dd2736cee95e06cd4c5a3ea";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_darwin_amd64.tar.gz";
              sha256 = "6ac4ab8871214942bc3edde176b3605f84468106d99b8a19fb969f082da6608d";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_darwin_arm64.tar.gz";
              sha256 = "d657a1818ceb928f412b9138abb9eda171b65745929fa3389aed397f2e2b2de6";
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
          toonVersion = "0.2.4";
          toonSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-linux-amd64.tar.xz";
              sha256 = "af6e21187c5afb6ec993b9e668d13d3b785f55571b67ced1c1e24bb53f0b1b62";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-linux-arm64.tar.xz";
              sha256 = "3ebc625a27ccf565eb649565aefef505ab40cddb63648a6bc0c8c54ae5bf9f57";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-darwin-amd64.tar.xz";
              sha256 = "e1af1cca9ea99df2eb85420fe5289c6d4adddad001b778a4c285e249acc57df8";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-darwin-arm64.tar.xz";
              sha256 = "fe163da70b7f504ad489aeea1e8887971df6b526b6bcdd0f37add9cdab7c2fce";
            };
          };
          toonSource = toonSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for toon: ${prev.stdenv.hostPlatform.system}");

          # ms - Meta Skill manager with Thompson sampling optimization
          # ms 0.2.2 stopped publishing an aarch64-unknown-linux-gnu asset;
          # msSource falls back to null and meta-skill guards on it.
          msVersion = "0.2.2";
          msSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/meta_skill/releases/download/v${msVersion}/ms-${msVersion}-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "12e92d23659ddb8a173f88b297f241d0ae7197c4bdddfdf3c530e1a39c3c59d7";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/meta_skill/releases/download/v${msVersion}/ms-${msVersion}-aarch64-apple-darwin.tar.gz";
              sha256 = "25f1f75b4d1e4377466ca85fe7d9fd9a485c1b6099bd3aa4b40e04b5c8836526";
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
          brVersion = "0.6.0";
          brSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-linux_amd64.tar.gz";
              sha256 = "16w2hi3nafhqc3l8di0i4y17zc8m7wb65v6g5m6yjcdf7dka3ygn";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-linux_arm64.tar.gz";
              sha256 = "1xa65fjzshfgjypq09g4f75micsly3270pm2mj2glpjsy015x1nx";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-darwin_amd64.tar.gz";
              sha256 = "0hz32s7j7zdips614l8iykv96bxmdqqspyqwak2fr1hvh7va17gr";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-darwin_arm64.tar.gz";
              sha256 = "07ijrlpn2k4841nizbw5rdwzagvqyrmvxhagaa4cq977cq1wj3is";
            };
          };
          brSource = brSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for br: ${prev.stdenv.hostPlatform.system}");

          # ntm - Named Tmux Manager for AI coding agent coordination
          ntmVersion = "1.35.1";
          ntmSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_linux_amd64.tar.gz";
              sha256 = "0i7dr308a5p6kgmd8s3zbdifqa1jsirql5lfhpqd4w0py7gi41wi";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_linux_arm64.tar.gz";
              sha256 = "173n3v4p03s7p7g9m5dy4v0b3qfzzjgb4a6w65pywvyy9d5mdkcp";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_darwin_amd64.tar.gz";
              sha256 = "0jpivxmysmradgq3wxlgkskxrznm7zfjyd7qbi104bklpfkvbmyi";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_darwin_arm64.tar.gz";
              sha256 = "0nac6rqcf3zghyksx7w3jir8fgzdfi5ljhb5ivpkhhyqxxgpr3kb";
            };
          };
          ntmSource = ntmSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for ntm: ${prev.stdenv.hostPlatform.system}");

          # dcg - destructive command guard
          dcgVersion = "0.14.4";
          dcgSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-x86_64-unknown-linux-musl.tar.xz";
              sha256 = "09daf765e21457a756e69cc9f8bce41635836c6b958f5b27c7a6a6a376cbde21";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-aarch64-unknown-linux-gnu.tar.xz";
              sha256 = "0cb6a4e851bb1626807e1c5fbfd6d565275383a7624228678f858570bf416e6f";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-x86_64-apple-darwin.tar.xz";
              sha256 = "d9b4e2e565f1e1853039b7c956fa4ce7576c7bb641382fe41ec44a0deabb5f07";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-aarch64-apple-darwin.tar.xz";
              sha256 = "b704fe0190bfeec51bc264a573fa3d620590286b2b2b63b2ca2293aa24aad013";
            };
          };
          dcgSource = dcgSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for dcg: ${prev.stdenv.hostPlatform.system}");

          # caam - coding agent account manager (instant auth switching)
          caamVersion = "0.1.18";
          caamSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_linux_amd64.tar.gz";
              sha256 = "65aaccb12ca344dd64df8d378f2d79d9e305a5d7345cd47fe4ac8f361c3dc43c";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_linux_arm64.tar.gz";
              sha256 = "2ec69ee05a6e37b12b2c03d0e53a4f107d0627c218e5388d89be71d11e34cca7";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_darwin_amd64.tar.gz";
              sha256 = "860138d80159689cccc98513e0a0f246ad98441a3f45caed756f209514bea972";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_darwin_arm64.tar.gz";
              sha256 = "f10acd6591aa808e4d486783e07695414b4ee92a28da697f33a86a83626f9106";
            };
          };
          caamSource = caamSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for caam: ${prev.stdenv.hostPlatform.system}");

          # agent-browser - browser automation CLI for AI agents
          agentBrowserVersion = "0.38.1";
          agentBrowserSources = {
            "x86_64-linux" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-linux-x64";
              sha256 = "18ay43wlj5k54am9jkza1is0626r6szlbrg4kn41q88336d1802i";
            };
            "aarch64-linux" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-linux-arm64";
              sha256 = "04a5cqjmfgp2z4mrv77bspldilxkz7zdq3cmyxi8l7knw1g32ywk";
            };
            "x86_64-darwin" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-darwin-x64";
              sha256 = "13paf9r0cdkapddwizm1j2jbw5wflpgfglpn1y46s2nsyy2zi1wi";
            };
            "aarch64-darwin" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-darwin-arm64";
              sha256 = "039fi5zaxvsrwqjzzk2mkrc0xbrld8n00xwysdjajgh5b5r2hq9f";
            };
          };
          agentBrowserSource = agentBrowserSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for agent-browser: ${prev.stdenv.hostPlatform.system}");

          # pi - coding agent CLI (Rust port of Mario Zechner's pi)
          piVersion = "0.3.0";
          piSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/pi_agent_rust/releases/download/v${piVersion}/pi-linux-amd64.tar.xz";
              sha256 = "0gbzpi6b75v154vnxhfvqrfxcbrir8l3d7g5z1lh0ynd4j1pnadl";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/pi_agent_rust/releases/download/v${piVersion}/pi-darwin-arm64.tar.xz";
              sha256 = "0blf80hnw3prnxsp7fmqxivds1a21dqs77a3g6bh7zdxfmhbp8sw";
            };
          };
          piSource = piSources.${prev.stdenv.hostPlatform.system} or null;

          # xf - cross-format file converter
          xfVersion = "0.4.1";
          xfSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/xf/releases/download/v${xfVersion}/xf-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "3855142061320cf8669ad0ad698b4762e2002f8fadde6befa717f0eede336e63";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/xf/releases/download/v${xfVersion}/xf-aarch64-apple-darwin.tar.gz";
              sha256 = "68b9c59fe03ea180ae64e26d076d615e9a462c8d27430f8e0a1d010c74199ebc";
            };
          };
          xfSource = xfSources.${prev.stdenv.hostPlatform.system} or null;

          # mcp-agent-mail - Rust replacement for Python mcp_agent_mail
          mcpAgentMailVersion = "0.3.36";
          mcpAgentMailSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/v${mcpAgentMailVersion}/mcp-agent-mail-x86_64-unknown-linux-gnu.tar.xz";
              sha256 = "0pijchy03jahy4jhi7zsygciw9s0cjhyb9y6z2c4njj3gx1462f8";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/v${mcpAgentMailVersion}/mcp-agent-mail-aarch64-apple-darwin.tar.xz";
              sha256 = "08v507xhzvgg0636lbvsnbmwlxgrz58785qvq84qag6xg1c5i41b";
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
          ompVersion = "18.2.11";
          ompSources = {
            "x86_64-linux" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v${ompVersion}/omp-linux-x64";
              sha256 = "0aisfd644c7zn3cyss8iwivcnsvy1cw1962cvlkq7ngkgdakkkwp";
            };
            "aarch64-linux" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v${ompVersion}/omp-linux-arm64";
              sha256 = "17lknf12l58dng1xcnmd4pdjyfwczcqq51rw99rd708019dgj5f1";
            };
            "x86_64-darwin" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v${ompVersion}/omp-darwin-x64";
              sha256 = "162zhcrj8wvg2zqiz05f55whzxqzbssnpd42g3dn0nhj2dr72w8j";
            };
            "aarch64-darwin" = {
              url = "https://github.com/can1357/oh-my-pi/releases/download/v${ompVersion}/omp-darwin-arm64";
              sha256 = "0a0a04mfc4w92k9ba7mr3qgdip76vwnxf9ziw99s5zsccxbzvvzs";
            };
          };
          ompSource = ompSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for omp: ${prev.stdenv.hostPlatform.system}");

          # pt - process triage (intelligent process termination)
          ptVersion = "2.1.0";
          ptSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/process_triage/releases/download/v${ptVersion}/pt-core-linux-x86_64-${ptVersion}.tar.gz";
              sha256 = "15xsyfhdr34wbpqqwv30nw57chms29s9abq8yrg0hd9c8c1wbn41";
            };
          };
          ptSource = ptSources.${prev.stdenv.hostPlatform.system} or null;

          # rch - remote compilation helper
          rchVersion = "2.0.0";
          rchSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/remote_compilation_helper/releases/download/v${rchVersion}/rch-v${rchVersion}-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "04qny501y2lz4bf00aqak5cnbjfmaafj3328l7kv4ng3m8v527r8";
            };
          };
          rchSource = rchSources.${prev.stdenv.hostPlatform.system} or null;
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
            ubsVersion = "5.3.13";
            ubsBaseUrl = "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/v${ubsVersion}";
            # Language modules (pinned to v${ubsVersion})
            ubsModules = {
              "ubs-js.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-js.sh"; sha256 = "1pq8lf3vkshwzphgl3v2qkmi8v2692jmjynppfqh159f4lasxykd"; };
              "ubs-python.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-python.sh"; sha256 = "0yrx9iszhkj17szcf8yq2h3nv44lmhgl973z66573i92lcyjky3i"; };
              "ubs-cpp.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-cpp.sh"; sha256 = "01aqm3yq4cb74vqpbj6rcz5jq9rhaihd8669llgyhrmci5qvfm7h"; };
              "ubs-rust.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-rust.sh"; sha256 = "0464drlb3wkl2jc7hzxm80g490qmqrp4n35c5qvwnwnmpblv3ll9"; };
              "ubs-golang.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-golang.sh"; sha256 = "0xsgc1df4cnhn6fv57wh23h8n7sp2351gpk52j12x4v1v5k78l52"; };
              "ubs-java.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-java.sh"; sha256 = "18plk8k04y9cp2q31z1ivmq4khflf6x852i4jym0rhnpf79g4vcx"; };
              "ubs-ruby.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-ruby.sh"; sha256 = "0n6kclb9k6bz593dqy8260h10lakxhj1495mf6zy1irsy5dyf6rd"; };
              "ubs-swift.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-swift.sh"; sha256 = "1h79j7s5r1g9sf748l9jirhnsjscm9npwxann1fp7am7kzib5f5b"; };
              "ubs-csharp.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-csharp.sh"; sha256 = "1xk1i2gzxpy3maa8cbzcfc29df6jn8d7wrjavarhqnpq5figljda"; };
              "ubs-elixir.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-elixir.sh"; sha256 = "1h4spmq2xpwd7dn9yk30d5nk94xy6r2qsxprxbi95lm9v1c9i52d"; };
            };
            # Helper assets (pinned to v${ubsVersion})
            ubsHelpers = {
              "helpers/resource_lifecycle_py.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_py.py"; sha256 = "0gj8034w6z8by725nwv1vsy4wcz2pmsq73wvkyhsd3wq5ks4z20y"; };
              "helpers/resource_lifecycle_go.go" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_go.go"; sha256 = "1g9q1qchpfaf1p9vzqahr7qh5mx9k5laaq4wgrd91mrdfwn5s88h"; };
              "helpers/resource_lifecycle_java.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_java.py"; sha256 = "1w9rvy1bgygp4ysw3dwi5x4k1ajai2gzjigsyv6539za34axl1f0"; };
              "helpers/resource_lifecycle_cpp.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_cpp.py"; sha256 = "1a6zyzmwmzb7qvj13l2l4gzd4xd6rv59lc4rjdc4ccm28y0g5jgg"; };
              "helpers/resource_lifecycle_csharp.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_csharp.py"; sha256 = "0a2zx6712dbalq8db58ddgyja6dwi9maahgrrj0nfq9ykl264dba"; };
              "helpers/resource_lifecycle_ruby.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_ruby.py"; sha256 = "1hhxkd1cplb5fnrfm035ykplcy43jvi097pllzdy8cy8r9dwvzxy"; };
              "helpers/resource_lifecycle_swift.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_swift.py"; sha256 = "03xxmzrkd76n3gh0m3brv5fda27lynzl1lh5bg8g1ynzmj1qx9rk"; };
              "helpers/type_narrowing_ts.js" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_ts.js"; sha256 = "0ydhlvc02a784pcmh42yi5z2zvyn5id7k5bj6xf0d73pz60xsfdy"; };
              "helpers/type_narrowing_rust.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_rust.py"; sha256 = "0zyl9fpgrq840gaqb7xsgfly1fsqga76l2wgjb9j533w697kia30"; };
              "helpers/type_narrowing_kotlin.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_kotlin.py"; sha256 = "0yddg1nai3f7cxi87vyic4jdvvlky6x5c2c3q9dd2jf3x21483vg"; };
              "helpers/type_narrowing_swift.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_swift.py"; sha256 = "06ml047rqw5l77j1nddwp7mgzc0iriyx6xwwfzj6869rjbxbll7r"; };
              "helpers/type_narrowing_csharp.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_csharp.py"; sha256 = "0b51bhgsr60yczfhn8j0d3wllzpg7034vd6wmmwzr3b0cxpw3c5r"; };
              "helpers/async_task_handles_csharp.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/async_task_handles_csharp.py"; sha256 = "08ihkphd7ywrlw21dfh5ac4a8bxxl4wnms8qrspkvard6lrgzvx1"; };
            };
          in prev.stdenv.mkDerivation {
            pname = "ubs";
            version = ubsVersion;

            src = prev.fetchurl {
              url = "${ubsBaseUrl}/ubs";
              sha256 = "47474fd2adee9be2af4796b656a68cb2074c95b9f50b8a7de492873b4528703f";
            };

            dontUnpack = true;

            nativeBuildInputs = [ prev.makeWrapper ];

            installPhase = ''
              mkdir -p $out/bin
              mkdir -p $out/share/ubs/modules/helpers

              # Install language modules (non-executable to prevent patchShebangs
              # from rewriting shebangs, which would break UBS checksum verification)
              ${prev.lib.concatStringsSep "\n" (prev.lib.mapAttrsToList (name: src: ''
                cp ${src} $out/share/ubs/modules/${name}
              '') ubsModules)}

              # Install helper assets
              ${prev.lib.concatStringsSep "\n" (prev.lib.mapAttrsToList (name: src: ''
                cp ${src} $out/share/ubs/modules/${name}
              '') ubsHelpers)}

              cp $src $out/bin/.ubs-unwrapped
              chmod +x $out/bin/.ubs-unwrapped
              wrapProgram $out/bin/.ubs-unwrapped \
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
                --replace-quiet "PLACEHOLDER_BIN" "$out/bin/.ubs-unwrapped" \
                --replace-quiet "PLACEHOLDER_DIR" "$out/share/ubs/modules"
              chmod +x $out/bin/ubs
            '';

            # Make modules executable after fixupPhase (patchShebangs) has run,
            # preserving original shebangs so UBS checksum verification passes.
            postFixup = ''
              chmod +x $out/share/ubs/modules/ubs-*.sh
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
            version = "1.3.1";

            src = prev.fetchurl {
              url = "https://github.com/Dicklesworthstone/repo_updater/releases/download/v1.3.1/ru";
              sha256 = "6ae3ae2d850d26c0ad82e3b5e713338f74f2bfd483691e4d09d9d75e00a79b3a";
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
              # 0.1.18+ tarballs extract to a versioned subdir (pi-<ver>-<triple>/pi)
              cp pi-*/pi $out/bin/pi
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
          # `minimal` (not `default`) is the core agent: `default` is the `full`
          # variant that pre-builds every optional integration (messaging, voice,
          # matrix, bedrock, ...), which is far more closure than a coding-agent
          # CLI needs on every machine. The messaging gateway deployments on
          # bali/hermes-fu use the upstream NixOS module, not this package.
          # No x86_64-darwin output upstream; null there and filtered by callers.
          hermes-agent =
            (inputs.hermes-agent.packages.${prev.stdenv.hostPlatform.system} or { }).minimal or null;

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
            codexVersion = "0.156.1";
            codexSources = {
              "x86_64-linux" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-linux-x64.tgz";
                hash = "sha256-3tmEC6vrUR55c4rnCARK5In7zlDbcAK5Q7MZXPWuaiU=";
                vendorDir = "x86_64-unknown-linux-musl";
              };
              "aarch64-linux" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-linux-arm64.tgz";
                hash = "sha256-PKPDqF4YRZTQtmXqkCi8OMSuiWkehu2+79LG9Yl5/LQ=";
                vendorDir = "aarch64-unknown-linux-musl";
              };
              "x86_64-darwin" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-darwin-x64.tgz";
                hash = "sha256-n+4m5z9aJLawVwRvDb5hn5S7AkuTTid/VPSTTQgUVNA=";
                vendorDir = "x86_64-apple-darwin";
              };
              "aarch64-darwin" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-darwin-arm64.tgz";
                hash = "sha256-iYI901A2TV4MuKdMHqWF7CtzB5MdncCsQZW4vI+eLfo=";
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

          # gemini-cli - Google Gemini coding agent CLI (pre-built JS bundle)
          gemini-cli = prev.stdenv.mkDerivation {
            pname = "gemini-cli";
            version = "0.60.0";

            src = prev.fetchzip {
              url = "https://github.com/google-gemini/gemini-cli/releases/download/v0.60.0/gemini-cli-bundle.zip";
              hash = "sha256-sxqMw44oUEoRZFo47ENSvJbEy3Z+uXbyoed4BpEakQQ=";
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
