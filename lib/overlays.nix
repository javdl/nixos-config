{ inputs }:
[
      # inputs.jujutsu.overlays.default
      # inputs.zig.overlays.default
      # nix-openclaw only supports x86_64-linux, x86_64-darwin, aarch64-darwin
      (final: prev:
        if builtins.elem prev.stdenv.hostPlatform.system ["x86_64-linux" "x86_64-darwin" "aarch64-darwin"]
        then (inputs.nix-openclaw.overlays.default final prev)
        else {}
      )

      (final: prev:
        let
          # Import nixpkgs-unstable with allowUnfree enabled
          pkgs-unstable = import inputs.nixpkgs-unstable {
            system = prev.stdenv.hostPlatform.system;
            config.allowUnfree = true;
          };

          # grepai - semantic code search CLI tool
          grepaiVersion = "0.35.0";
          grepaiSources = {
            "x86_64-linux" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_linux_amd64.tar.gz";
              sha256 = "1cirq9gy4k5fb53n86xmkxkq0835l7z4yxq7hb4v17bxgazy0c58";
            };
            "aarch64-linux" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_linux_arm64.tar.gz";
              sha256 = "0jmamir89h6l2wjznpj4x3mamn6kdajiyxjzhbpxbdvcycchw25s";
            };
            "x86_64-darwin" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_darwin_amd64.tar.gz";
              sha256 = "0mwwya2r0yl6njfq72h9s9ivnn67hjfk4rl2dcyxn06xsm1fx9nv";
            };
            "aarch64-darwin" = {
              url = "https://github.com/yoanbernabeu/grepai/releases/download/v${grepaiVersion}/grepai_${grepaiVersion}_darwin_arm64.tar.gz";
              sha256 = "1zdwqm2bi5bxnz45vy7vzggv5914b4za2yrr21dbkl44p71blwz8";
            };
          };
          grepaiSource = grepaiSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for grepai: ${prev.stdenv.hostPlatform.system}");

          # beads_viewer (bv) - TUI for beads issue tracking
          bvVersion = "0.15.2";
          bvSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_linux_amd64.tar.gz";
              sha256 = "0kk6lxc904j3mxxjxp7df4hq9swib8rj5srqsqayk6f5fbp7sz26";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_linux_arm64.tar.gz";
              sha256 = "1gj1fjs6df2i0ipvlc05wj5cq5s0lwmkcif4an5v0m6xrqkv7jab";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_darwin_amd64.tar.gz";
              sha256 = "1lpphsis977j7kva1xic0cwws0mawylp3l34fzv9s0g21imih78d";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_darwin_arm64.tar.gz";
              sha256 = "1jz29wn35n9pnc39gbjgqxph2x787xnqkx1y8icqfzwbnwprgpaf";
            };
          };
          bvSource = bvSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for bv: ${prev.stdenv.hostPlatform.system}");

          # cass - coding agent session search
          cassVersion = "0.2.2";
          cassSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-linux-amd64.tar.gz";
              sha256 = "0cs0g447v91irv39d7kafn919aici6zw7kqck9j7h6njlkm8kr3i";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-linux-arm64.tar.gz";
              sha256 = "1ba6bn1ajj1lss6rmvdzm4vzk5vjjhz0j24gzhzk1zbhc7mi57x2";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-darwin-arm64.tar.gz";
              sha256 = "0cm844ndsmjqa9j4mlz63yvi6pq4yc1xivshpm1l3dajh2q9r9vz";
            };
          };
          cassSource = cassSources.${prev.stdenv.hostPlatform.system} or null;

          # slb - Shannon Language Benchmark for LLM evaluation
          slbVersion = "0.2.0";
          slbSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_linux_amd64.tar.gz";
              sha256 = "9ceed8af0ec18b425bafda9bb6b289e1e42faec8584d84c4fea529fc1ca25597";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_linux_arm64.tar.gz";
              sha256 = "ba8d8ad2fdf6ffaf7556c55e5d5283893a8dfe1e30f41fc981fc3e28882e01fa";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_darwin_amd64.tar.gz";
              sha256 = "39ecce943d9924c555a97184ea0745751048ca0a9acc8413ee4310afe2e1bed1";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_darwin_arm64.tar.gz";
              sha256 = "0898545c20c9fe867cfb713e8fe94772dfc5da60dd9eee4a1dcaaffccf86386a";
            };
          };
          slbSource = slbSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for slb: ${prev.stdenv.hostPlatform.system}");

          # csctf - Chat Shared Conversation To File
          csctfVersion = "0.4.5";
          csctfSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/chat_shared_conversation_to_file/releases/download/v${csctfVersion}/csctf-linux-x64";
              sha256 = "bb58bbd35de1d408b5fede47c61a7ff89038983043d8f735888d72a095b7fef3";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/chat_shared_conversation_to_file/releases/download/v${csctfVersion}/csctf-linux-arm64";
              sha256 = "3dc185dd7eb466fc6c6f77d388fd6e76628a1e1ddd3248869ae9b6792df76875";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/chat_shared_conversation_to_file/releases/download/v${csctfVersion}/csctf-macos-x64";
              sha256 = "42075d7ef82c3b17a6419a4033b7a219478ce162fb605668f0048843b06a5265";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/chat_shared_conversation_to_file/releases/download/v${csctfVersion}/csctf-macos-arm64";
              sha256 = "d5d88aeb20c13bded9e186b89a3c0d7f00705fbc658ee5a41766a84f7da90e7c";
            };
          };
          csctfSource = csctfSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for csctf: ${prev.stdenv.hostPlatform.system}");

          # brenner - Sydney Brenner research platform CLI
          brennerVersion = "0.3.0";
          brennerSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-linux-x64";
              sha256 = "fac82298dd5daabc798aab45ab0b724d600f39e65ffddbc8a2d2f8cfc5f95cb4";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-linux-arm64";
              sha256 = "8e359b523703e350963e4d78098c0d7ff768c7224ead6aaf47a1c4ed52f42324";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-darwin-x64";
              sha256 = "fff8aa65c9ab8b193b37a1a8b7e29a732fbcacf73a2d42e631ed7553fedf7947";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-darwin-arm64";
              sha256 = "e321c7063ea092a75a7a07d292b3e1949b4bbf38409c0a8a12314634384b580b";
            };
          };
          brennerSource = brennerSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for brenner: ${prev.stdenv.hostPlatform.system}");

          # toon - Token-Optimized Object Notation converter (JSON <-> TOON)
          toonVersion = "0.2.1";
          toonSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-linux-amd64.tar.xz";
              sha256 = "f547b4ae9ce241a7317f4a0d2cacfbf335ccb85d7941558f44830ecb47f65fe3";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-linux-arm64.tar.xz";
              sha256 = "7d3d94a9b24ff2b7d5ec60c1bc2bc3fbec750449dc619922bfd1377f74adbe2a";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-darwin-amd64.tar.xz";
              sha256 = "704c6b4113147faff8fbe1540157583d2347c34668b4bec9a0e3bba471ef582c";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-darwin-arm64.tar.xz";
              sha256 = "8bd9b439f560243525f35bca2bba117ddb6085d0d45eabc450cb29a715006ab5";
            };
          };
          toonSource = toonSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for toon: ${prev.stdenv.hostPlatform.system}");

          # ms - Meta Skill manager with Thompson sampling optimization
          msVersion = "0.1.0";
          msSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/meta_skill/releases/download/v${msVersion}/ms-${msVersion}-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "c793ba2c37575d5799d820853cb411a40dc9ba660741fe36b557efda706c794f";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/meta_skill/releases/download/v${msVersion}/ms-${msVersion}-aarch64-apple-darwin.tar.gz";
              sha256 = "31df557201b4466a079e218c703d83c4feb11ff9626963f04152be14ce9d95f8";
            };
          };
          msSource = msSources.${prev.stdenv.hostPlatform.system} or null;

          # gws - Google Workspace CLI
          gwsVersion = "0.16.0";
          gwsSources = {
            "x86_64-linux" = {
              url = "https://github.com/googleworkspace/cli/releases/download/v${gwsVersion}/gws-x86_64-unknown-linux-musl.tar.gz";
              sha256 = "0rppgb31mdd0vpyr8kizx3isznaark6407irim832n6dl9hlrz19";
              dir = "gws-x86_64-unknown-linux-musl";
            };
            "aarch64-linux" = {
              url = "https://github.com/googleworkspace/cli/releases/download/v${gwsVersion}/gws-aarch64-unknown-linux-musl.tar.gz";
              sha256 = "0904pd8z56zbvffzznf7hdx7s6lb1b3cq048spihi1jpqfh86ndz";
              dir = "gws-aarch64-unknown-linux-musl";
            };
            "x86_64-darwin" = {
              url = "https://github.com/googleworkspace/cli/releases/download/v${gwsVersion}/gws-x86_64-apple-darwin.tar.gz";
              sha256 = "07kn45p9bmzf6vv9nk18l7y8z87cqq2cwm9rm224k684c6ghh6qg";
              dir = "gws-x86_64-apple-darwin";
            };
            "aarch64-darwin" = {
              url = "https://github.com/googleworkspace/cli/releases/download/v${gwsVersion}/gws-aarch64-apple-darwin.tar.gz";
              sha256 = "0z3dbjvp4nw5fch54q2vg2q77j90ssprd3abvjvzy1hgsaadsav0";
              dir = "gws-aarch64-apple-darwin";
            };
          };
          gwsSource = gwsSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for gws: ${prev.stdenv.hostPlatform.system}");

          # beads_rust (br) - fast Rust port of beads issue tracker
          brVersion = "0.1.45";
          brSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-v${brVersion}-linux_amd64.tar.gz";
              sha256 = "14g39q2lwnkisi2ckaqp0ljlr29y16r5qi3p22xqk9i3q5vs53sp";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-v${brVersion}-linux_arm64.tar.gz";
              sha256 = "1hd2kyh5ivc35iqwf12hcf08x7vpa2w0vf9rd0c3f1klrvl3z088";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-v${brVersion}-darwin_amd64.tar.gz";
              sha256 = "0hd7m4fgja7mwvz4vwg7rxiraq15qvlvikclz2kjjpi0vbhaz287";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-v${brVersion}-darwin_arm64.tar.gz";
              sha256 = "1c5kvmbmzywb0a4ri1v0zxca92vhnfvls1ncjd60fkawkq3shkc9";
            };
          };
          brSource = brSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for br: ${prev.stdenv.hostPlatform.system}");

          # ntm - Named Tmux Manager for AI coding agent coordination
          ntmVersion = "1.8.0";
          ntmSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_linux_amd64.tar.gz";
              sha256 = "1ffpi7jp9a1bb5r6hafxjyhhj6smzblrsf0d147gzqjj7nb9kvl6";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_linux_arm64.tar.gz";
              sha256 = "1wj32kk05xix0fg694wnanx8ja2h3iiw4886rwhj23mll0hyss70";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_darwin_all.tar.gz";
              sha256 = "1iq02h26whh7xcp8r3fazfjzphfmhdj8jh3kp9ydq14m5fxhn2az";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_darwin_all.tar.gz";
              sha256 = "1iq02h26whh7xcp8r3fazfjzphfmhdj8jh3kp9ydq14m5fxhn2az";
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
          agentBrowserVersion = "0.20.13";
          agentBrowserSources = {
            "x86_64-linux" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-linux-x64";
              sha256 = "16dds3b3l20s42v77j67rxapg3ij1lrhvwgk37dcfpxlq92vmi1m";
            };
            "aarch64-linux" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-linux-arm64";
              sha256 = "11m8j89iimadqjsj9ivpp4yr8f1l5hikz0la4mfsd10c3ikpknzr";
            };
            "x86_64-darwin" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-darwin-x64";
              sha256 = "0w4jbldrhc7n757n525jgnsc0x361qfxay3vj3m2pv4ff0jy81cv";
            };
            "aarch64-darwin" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-darwin-arm64";
              sha256 = "1p229rnqqndhr4id89rs5m51vc68wia8q3ny1w7xhk7vmimj5g45";
            };
          };
          agentBrowserSource = agentBrowserSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for agent-browser: ${prev.stdenv.hostPlatform.system}");

          # pi - prompt injection detection agent (Rust)
          piVersion = "0.1.9";
          piSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/pi_agent_rust/releases/download/v${piVersion}/pi-linux-amd64.tar.xz";
              sha256 = "1m3fhwv5igx2sphxkzh8m8zww1wywsjcvkgzsak0dkpl2bhg09xn";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/pi_agent_rust/releases/download/v${piVersion}/pi-darwin-arm64.tar.xz";
              sha256 = "0ds4xa8j01r3f5ncnmc87rj1114aq657gzww8xd8lsvl71lfhrf4";
            };
          };
          piSource = piSources.${prev.stdenv.hostPlatform.system} or null;

          # xf - cross-format file converter
          xfVersion = "0.2.0";
          xfSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/xf/releases/download/v${xfVersion}/xf-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "e8de166f4464ec46ae6b38d89194e5312f0cce06ae5398df48527d26d5bbe299";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/xf/releases/download/v${xfVersion}/xf-x86_64-apple-darwin.tar.gz";
              sha256 = "c85c11d4be13fdda3588aeb6d9d5ff62aac150c60e9f1253c2c710882e05b2ce";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/xf/releases/download/v${xfVersion}/xf-aarch64-apple-darwin.tar.gz";
              sha256 = "e90a04cb49e0910766b573d41338779ca22a6c29076a211eaa7148b637eb1674";
            };
          };
          xfSource = xfSources.${prev.stdenv.hostPlatform.system} or null;

          # mcp-agent-mail - Rust replacement for Python mcp_agent_mail
          mcpAgentMailVersion = "0.2.7";
          mcpAgentMailSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/v${mcpAgentMailVersion}/mcp-agent-mail-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "1f6a08z138bmyz5lqnvlbyy5cjb8lmjkz4pwyy1dv8rs1lfy8sjs";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/v${mcpAgentMailVersion}/mcp-agent-mail-aarch64-apple-darwin.tar.gz";
              sha256 = "0rp0r4h9g7pv5xyrjd99mf43dp4jldiq29yaw4zw5y9ym9xmx9x3";
            };
          };
          mcpAgentMailSource = mcpAgentMailSources.${prev.stdenv.hostPlatform.system} or null;

          # frankensearch (fsfs) - full-text search engine
          frankensearchVersion = "1.1.2";
          frankensearchSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/frankensearch/releases/download/v${frankensearchVersion}/fsfs-${frankensearchVersion}-x86_64-unknown-linux-musl.tar.xz";
              sha256 = "1d6c0f70812b2b27a30cac6738de2400104c5aa16c52b0d10b85b87edaa7bc06";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/frankensearch/releases/download/v${frankensearchVersion}/fsfs-${frankensearchVersion}-aarch64-apple-darwin.tar.xz";
              sha256 = "aee1647692f6ce44e88b41ed945cc1f1025777e6c76add290fb9875ee46eadd9";
            };
          };
          frankensearchSource = frankensearchSources.${prev.stdenv.hostPlatform.system} or null;

          # casr - cross agent session resumer
          casrVersion = "0.1.1";
          casrSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/cross_agent_session_resumer/releases/download/v${casrVersion}/casr-x86_64-unknown-linux-musl.tar.xz";
              sha256 = "7ae074154c7de4febd1346f0173e155025e42c0c5c19ab72fc7fe3f68df984ec";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/cross_agent_session_resumer/releases/download/v${casrVersion}/casr-aarch64-apple-darwin.tar.xz";
              sha256 = "b049d4a05a4ca59eb0a2536767b9289ed3a55c4a6e980d3756ba96d0ad385dfd";
            };
          };
          casrSource = casrSources.${prev.stdenv.hostPlatform.system} or null;

          # s2p - source to prompt TUI (bare binary, no tarball)
          s2pVersion = "0.3.2";
          s2pSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/source_to_prompt_tui/releases/download/v${s2pVersion}/s2p-linux-x64";
              sha256 = "0f1q10b1bffs9c0hsp5glljdc7qi959j3wg7jf0mkcflr6lbhydw";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/source_to_prompt_tui/releases/download/v${s2pVersion}/s2p-linux-arm64";
              sha256 = "13bi0rsc7am8mq6ix2qw22m8hbibrj3wrs1g4mxrkayldj456yqb";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/source_to_prompt_tui/releases/download/v${s2pVersion}/s2p-macos-x64";
              sha256 = "0cgd8c55zcm7d9s4pi55144h322kiwl2bglfvhi687br3xy46s0d";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/source_to_prompt_tui/releases/download/v${s2pVersion}/s2p-macos-arm64";
              sha256 = "1j70lj8gkkvl8fnxfgqn7i10djhw6zg7z82dx9wf17crqfw20j4w";
            };
          };
          s2pSource = s2pSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for s2p: ${prev.stdenv.hostPlatform.system}");

          # pt - process triage (intelligent process termination)
          ptVersion = "2.0.5";
          ptSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/process_triage/releases/download/v${ptVersion}/pt-core-linux-x86_64-${ptVersion}.tar.gz";
              sha256 = "081wfy03dwak5sijrs9wmbs9yjsr0pfvlmh5lmvvg1zy8ppb9jjz";
            };
          };
          ptSource = ptSources.${prev.stdenv.hostPlatform.system} or null;

          # rch - remote compilation helper
          rchVersion = "1.0.10";
          rchSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/remote_compilation_helper/releases/download/v${rchVersion}/rch-v${rchVersion}-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "0kv9wrfx5y9qlx5c6y8zjlc2dp1aw22d6l2xd8rncdm7kw4qlqhd";
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
            ubsVersion = "5.0.6";
            ubsBaseUrl = "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/v${ubsVersion}";
            # Language modules (from v5.0.6 tag)
            ubsModules = {
              "ubs-js.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-js.sh"; sha256 = "1h1q58rx907kxbbjksbfg0ic2irrvblxxmjmgwkrckbriqqqja7r"; };
              "ubs-python.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-python.sh"; sha256 = "0hwsdkfpkxvpzb0lggkzk8i95vjnhs3vy5yb7r0hwavs7bwplsg7"; };
              "ubs-cpp.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-cpp.sh"; sha256 = "0a3gira5g344dl8r1xp5968wi569hcg4qx8q9nr2xz5q7hz22smc"; };
              "ubs-rust.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-rust.sh"; sha256 = "1w42wxqs18dvgvaa8w0630xsmk3psrix5fmr1358mhcccgsga3aw"; };
              "ubs-golang.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-golang.sh"; sha256 = "1ipl3zi3cqypgqv7qvnfmbrsi6567l5wv9njmp44chk8ybldcmxi"; };
              "ubs-java.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-java.sh"; sha256 = "0mkjndc64xvy0jblf1myk91w245bms45ha8dz3jlb78rppb0n4kb"; };
              "ubs-ruby.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-ruby.sh"; sha256 = "01alh2fqrwks4ljzz6jc09b6syyvifncxm433b876j2g2xmab41l"; };
              "ubs-swift.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-swift.sh"; sha256 = "0alaih98hngf7yd7vz70afpfqr28zxq7rbsfr6i9cpvj8apc4l5k"; };
            };
            # Helper assets (from v5.0.6 tag)
            ubsHelpers = {
              "helpers/resource_lifecycle_py.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_py.py"; sha256 = "0gj8034w6z8by725nwv1vsy4wcz2pmsq73wvkyhsd3wq5ks4z20y"; };
              "helpers/resource_lifecycle_go.go" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_go.go"; sha256 = "1g9q1qchpfaf1p9vzqahr7qh5mx9k5laaq4wgrd91mrdfwn5s88h"; };
              "helpers/resource_lifecycle_java.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_java.py"; sha256 = "1w9rvy1bgygp4ysw3dwi5x4k1ajai2gzjigsyv6539za34axl1f0"; };
              "helpers/type_narrowing_ts.js" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_ts.js"; sha256 = "0cgn5chgmar758dg4rkqq7nc8g1a89zsd8l0hy3dv689zgsfqag1"; };
              "helpers/type_narrowing_rust.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_rust.py"; sha256 = "0zv422w0q6x8cshw7s72674i4il50lvvi70ncdy9myyzwq6dcnim"; };
              "helpers/type_narrowing_kotlin.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_kotlin.py"; sha256 = "0yddg1nai3f7cxi87vyic4jdvvlky6x5c2c3q9dd2jf3x21483vg"; };
              "helpers/type_narrowing_swift.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_swift.py"; sha256 = "06ml047rqw5l77j1nddwp7mgzc0iriyx6xwwfzj6869rjbxbll7r"; };
            };
          in prev.stdenv.mkDerivation {
            pname = "ubs";
            version = ubsVersion;

            src = prev.fetchurl {
              url = "${ubsBaseUrl}/ubs";
              sha256 = "ebb31bf412a409a19a060f2587c2ea02f185c0bf695204db6c73ef7560d377ed";
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

          # cm - cass memory system
          # Pre-built GitHub release binaries are broken (bun cross-compilation doesn't embed scripts).
          # Build from source using bun in a plain derivation with fixed-output hash for deps.
          cass-memory = if prev.stdenv.isLinux && prev.stdenv.hostPlatform.system == "x86_64-linux" then
          let
            src = prev.fetchFromGitHub {
              owner = "Dicklesworthstone";
              repo = "cass_memory_system";
              rev = "v0.2.3";
              hash = "sha256-sVLYU68Vw3nSIcYBGAxP/OIaJBOJ7Kmjfzn/gOSPgDs=";
            };
            # Fixed-output derivation for bun install (needs network)
            bunDeps = prev.stdenv.mkDerivation {
              pname = "cass-memory-bun-deps";
              version = "0.2.3";
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
              outputHash = "sha256-BOkyY/cjghC+caQaSdcwiHwfqRsbnnyiHdPlG3yybNc=";
            };
          in prev.stdenv.mkDerivation {
            pname = "cass-memory";
            version = "0.2.3";
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

          # frankenterm (ft) - swarm-native terminal for AI agent orchestration
          # Cannot build from source: Cargo.lock has local git path deps (file:///dp/frankensearch)
          # Install via: cargo install --git https://github.com/Dicklesworthstone/frankenterm ft
          frankenterm = null;

          # franken_whisper - Agent-first Rust ASR orchestration (wraps whisper.cpp/insanely-fast-whisper/whisper-diarization)
          # Needs backend setup (whisper.cpp, Python venvs, HF tokens) - clone and run from folder
          # git clone https://github.com/Dicklesworthstone/franken_whisper && cd franken_whisper && cargo run -- robot health
          franken-whisper = null;

          # frankensqlite - Rust reimplementation of SQLite with concurrent writers
          # Cannot build: requires Rust nightly (#![feature(unix_socket_ancillary_data)])
          # Install via: cargo +nightly install --git https://github.com/Dicklesworthstone/frankensqlite
          frankensqlite = null;

          # frankentui (ftui) - minimal TUI kernel for flicker-free terminal UIs
          # Cannot build from source: no Cargo.lock in repo
          # Install via: git clone https://github.com/Dicklesworthstone/frankentui && cd frankentui && cargo run -p ftui-demo-showcase
          frankentui = null;

          # giil - git intelligent issue linker (x86_64-linux only)
          giil = if prev.stdenv.hostPlatform.system == "x86_64-linux" then prev.stdenv.mkDerivation {
            pname = "giil";
            version = "3.1.0";

            src = prev.fetchurl {
              url = "https://github.com/Dicklesworthstone/giil/releases/download/v3.1.0/giil";
              sha256 = "93c5abcc628996960a4236124ef1f9b73e561d73fb1b2b99f31286d34d3cee67";
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

          # pi - prompt injection detection agent (Rust)
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
              cp pi $out/bin/
              chmod +x $out/bin/pi
            '';

            meta = with prev.lib; {
              description = "Prompt injection detection agent";
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
              tar xzf $src
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

          # frankensearch (fsfs) - full-text search engine
          frankensearch = if frankensearchSource != null then prev.stdenv.mkDerivation {
            pname = "frankensearch";
            version = frankensearchVersion;

            src = prev.fetchurl {
              url = frankensearchSource.url;
              sha256 = frankensearchSource.sha256;
            };

            sourceRoot = ".";

            unpackPhase = ''
              ${prev.xz}/bin/xz -d < $src | tar xf -
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp fsfs $out/bin/
              chmod +x $out/bin/fsfs
            '';

            meta = with prev.lib; {
              description = "Full-text search engine";
              homepage = "https://github.com/Dicklesworthstone/frankensearch";
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
              platforms = [ "x86_64-linux" "aarch64-darwin" ];
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
            codexVersion = "0.114.0";
            codexSources = {
              "x86_64-linux" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-linux-x64.tgz";
                hash = "sha256-IAsvVZnT/HBwAsrGZhNQe5taFs2RVMffu7zbFwYLCL0=";
                vendorDir = "x86_64-unknown-linux-musl";
              };
              "aarch64-linux" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-linux-arm64.tgz";
                hash = "sha256-BbKaOAYkIVXpmQVF46yXg9Zmvz/ZKQkBmvjKd+JalX8=";
                vendorDir = "aarch64-unknown-linux-musl";
              };
              "x86_64-darwin" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-darwin-x64.tgz";
                hash = "sha256-c8jsJrGeZPc5XvPGyt/AOYdauaVoZ5ST895Z3FdeSGk=";
                vendorDir = "x86_64-apple-darwin";
              };
              "aarch64-darwin" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-darwin-arm64.tgz";
                hash = "sha256-T9IVepFpw4jg6o3+1Cd41qQ173SnQ7kfwWcPOXcIeOo=";
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
            version = "0.32.1";

            src = prev.fetchurl {
              url = "https://github.com/google-gemini/gemini-cli/releases/download/v0.32.1/gemini.js";
              hash = "sha256-9GpzzqY+5vvDhSsKnK1jOvx5QXWeG3y7QB2UYK/rZ28=";
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

          # cco - Claude Code sandbox (bubblewrap on Linux, sandbox-exec on macOS)
          cco = prev.stdenv.mkDerivation {
            pname = "cco";
            version = "0-unstable-2025-06-14";

            src = prev.fetchFromGitHub {
              owner = "nikvdp";
              repo = "cco";
              rev = "0b7265e4d629328a558364d86bb6a7f9a16b050b";
              sha256 = "1jjldvid6zyky5kb6nfa5128kml8sgpkkd047s98lkqajxmy5xvf";
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

          # ironclaw - security-focused personal AI assistant (built from source)
          ironclaw = let
            ironclawVersion = "0.18.0";
          in pkgs-unstable.rustPlatform.buildRustPackage {
            pname = "ironclaw";
            version = ironclawVersion;

            src = prev.fetchFromGitHub {
              owner = "nearai";
              repo = "ironclaw";
              rev = "v${ironclawVersion}";
              hash = "sha256-XFvrhu8MBQhTpK3lQxVLJ83C10Rh18cWrzkiWeOde1k=";
            };

            cargoHash = "sha256-0Fdj9+UVKrNi3X77MOxA5Az87Rw8wKnTp2W42eTD4TI=";

            # Only build with postgres feature (skip libsql to avoid cmake complexity)
            buildFeatures = [ "postgres" "html-to-markdown" ];
            buildNoDefaultFeatures = true;

            # Remove channels-src so build.rs skips WASM compilation (early return).
            # Telegram/Slack are built directly into the binary via teloxide/Slack crates.
            postPatch = ''
              rm -rf channels-src/
            '';

            nativeBuildInputs = with prev; [
              pkg-config
              cmake
              perl
            ];

            buildInputs = with prev; [
              openssl
              dbus
            ];

            # Skip tests (need database)
            doCheck = false;

            meta = with prev.lib; {
              description = "Security-focused personal AI assistant";
              homepage = "https://github.com/nearai/ironclaw";
              license = with licenses; [ mit asl20 ];
              platforms = [ "x86_64-linux" "aarch64-linux" ];
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

        })
]
