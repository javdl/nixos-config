{ inputs }:
[
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
          bvVersion = "0.17.0";
          bvSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_linux_amd64.tar.gz";
              sha256 = "079mqichhg79f273v13kbs6w5i9g687iqsmy2a4j4j32pawb1yjq";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_linux_arm64.tar.gz";
              sha256 = "1zrbhprzcy06m9gbk7hskwry5fi6qrfcm4skmkjhn9sv9vpafdan";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_darwin_amd64.tar.gz";
              sha256 = "1zaycdz6is79fzb6jav984f725db9wg5nvjis9khq5rb8kxcq60h";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_viewer/releases/download/v${bvVersion}/bv_${bvVersion}_darwin_arm64.tar.gz";
              sha256 = "167n6nbhk1kfhgsq5xsx5gg9r498gqry0zajdkp61ad8k4clny46";
            };
          };
          bvSource = bvSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for bv: ${prev.stdenv.hostPlatform.system}");

          # cass - coding agent session search
          cassVersion = "0.6.13";
          cassSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-linux-amd64.tar.gz";
              sha256 = "1ifli5g7hb8r93zdc7c90mwbz5b9nnfnc8gbljvl2ds4hqpyp8c9";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-linux-arm64.tar.gz";
              sha256 = "0lfh1rji1vpxl09ycys14shr2159zcr1k5sa22a8c9r9g9qhj0vr";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/download/v${cassVersion}/cass-darwin-arm64.tar.gz";
              sha256 = "0viskn46nahzsz1vcikdjkjah387l56fl7xrs7hq39rrfwy5rkja";
            };
          };
          cassSource = cassSources.${prev.stdenv.hostPlatform.system} or null;

          # slb - Shannon Language Benchmark for LLM evaluation
          slbVersion = "0.3.1";
          slbSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_linux_amd64.tar.gz";
              sha256 = "0b9c489fe025d77c8e0d6b992b2cd94d46e74a2a294e480c57274df5d634027b";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_linux_arm64.tar.gz";
              sha256 = "88f3ec9cb5fa03431b13ed840423c7d0946ca32b4a3dcc0edd5a0f934419917d";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_darwin_amd64.tar.gz";
              sha256 = "c8c2d745a95d702b65c6ae42fe8f8c56633ce2585857fe635af9a8a3e6ae9109";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/slb/releases/download/v${slbVersion}/slb_${slbVersion}_darwin_arm64.tar.gz";
              sha256 = "185bef18d345f406692430929860edbfc092a9e9406b868471eed2365e438bc6";
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
          brennerVersion = "0.4.0";
          brennerSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-linux-x64";
              sha256 = "2c5a5f01987c30933228d4b62c80e2d20ad872af60bd83604daa6b370e1f8ca3";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-linux-arm64";
              sha256 = "70595c1a82961db9fa4defe5675b01bbe0e0cc0875e8e33f4f02bb8273e64caa";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-darwin-x64";
              sha256 = "8c00ef0dd923389a8870c58514af54c5ff771c056c81106938627428ce71b501";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/brenner_bot/releases/download/v${brennerVersion}/brenner-darwin-arm64";
              sha256 = "1cf5e88d600c488999d341cb8e5a256d54127739de1c7ea6d12853dc9442b916";
            };
          };
          brennerSource = brennerSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for brenner: ${prev.stdenv.hostPlatform.system}");

          # toon - Token-Optimized Object Notation converter (JSON <-> TOON)
          toonVersion = "0.2.3";
          toonSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-linux-amd64.tar.xz";
              sha256 = "069e4b7f4a10c46f0f06fcf85f8511638a831b931579edf6cae606d27d11f0bf";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-linux-arm64.tar.xz";
              sha256 = "41b6cbae1358e62508e3833d84b16593e04716b4f1ee1fbd832655c632ad8877";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-darwin-amd64.tar.xz";
              sha256 = "9f60a8b9ae75a890412b16fe5e4e2b2966dddac145b7c98b9490e7f66ad922f1";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/toon_rust/releases/download/v${toonVersion}/toon-darwin-arm64.tar.xz";
              sha256 = "f5727108b549e135cace95b916c9d1b1f8ceb2cbd8b18ec3c6e3bbee9369590f";
            };
          };
          toonSource = toonSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for toon: ${prev.stdenv.hostPlatform.system}");

          # ms - Meta Skill manager with Thompson sampling optimization
          msVersion = "0.1.3";
          msSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/meta_skill/releases/download/v${msVersion}/ms-${msVersion}-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "f5edd16cc6264a532f6a32b5c5b3fbc9bd0e7badea5a542522f531baf58ecf0f";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/meta_skill/releases/download/v${msVersion}/ms-${msVersion}-aarch64-apple-darwin.tar.gz";
              sha256 = "9d58faab4c5be52935d78b4ced34b0ecae1eed8f6b97a901473b983bbb06f5da";
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
          brVersion = "0.2.15";
          brSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-linux_amd64.tar.gz";
              sha256 = "0rx6nh1wskafppjbj6fq9kbss51fwpkqfnfw2w3d90kzmvm0il1q";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-linux_arm64.tar.gz";
              sha256 = "107qg6ma930pdyzzn5d0ayd06h13i2hf88x8x8j460g6x8pkwk1k";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-darwin_amd64.tar.gz";
              sha256 = "0pfsza4fyxmc0f51hvk30s20m11r02rh4ay05hkh265aqrgqgdih";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/beads_rust/releases/download/v${brVersion}/br-${brVersion}-darwin_arm64.tar.gz";
              sha256 = "17485fqlkm2y72vzmkv4zpv5lva5vg9q9yp02nz2ha6a3qzi6cjf";
            };
          };
          brSource = brSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for br: ${prev.stdenv.hostPlatform.system}");

          # ntm - Named Tmux Manager for AI coding agent coordination
          ntmVersion = "1.18.3";
          ntmSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_linux_amd64.tar.gz";
              sha256 = "1iy0pmjgq4xkcjmi2srbkvfl9ar542sr33sgih9n7344nmsnb8b9";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_linux_arm64.tar.gz";
              sha256 = "1pds5v6599k05bpbrbyca2zxa3rfndv54b36hj2mg9dcdxhq4z6s";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_darwin_all.tar.gz";
              sha256 = "0054v2v389z1361288rria9rncxyzpyf0vdzkihkz7r1r905rihy";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/ntm/releases/download/v${ntmVersion}/ntm_${ntmVersion}_darwin_all.tar.gz";
              sha256 = "0054v2v389z1361288rria9rncxyzpyf0vdzkihkz7r1r905rihy";
            };
          };
          ntmSource = ntmSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for ntm: ${prev.stdenv.hostPlatform.system}");

          # dcg - destructive command guard
          dcgVersion = "0.5.7";
          dcgSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-x86_64-unknown-linux-musl.tar.xz";
              sha256 = "3cb7297ac90a01b82e6165b5ee0a74b8b673250e4a0ab9182d5dbe396a467cde";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-aarch64-unknown-linux-gnu.tar.xz";
              sha256 = "20b5b5cc53663d17cbfe0fa84c125ce868b2e02d009edfcb8fa83f9ab4087572";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-x86_64-apple-darwin.tar.xz";
              sha256 = "d3284f41e90b5329d52e1db97b0975797f75fd554fc306af4f00ce9cd3c691ab";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${dcgVersion}/dcg-aarch64-apple-darwin.tar.xz";
              sha256 = "0fe51d2ea47d5230ae8c2d30cddbe076daa2a1be04846e9352968b0d9a5df283";
            };
          };
          dcgSource = dcgSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for dcg: ${prev.stdenv.hostPlatform.system}");

          # caam - coding agent account manager (instant auth switching)
          caamVersion = "0.1.11";
          caamSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_linux_amd64.tar.gz";
              sha256 = "e0a4e7e3e27c6b3e4f36f7e69ac23f3d59135702d713109de4a4431422a02845";
            };
            "aarch64-linux" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_linux_arm64.tar.gz";
              sha256 = "65e7808cd8d90e06ba10bb755f728ac55c4ff2c97f4bc50b7af8cf56b0e2f242";
            };
            "x86_64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_darwin_amd64.tar.gz";
              sha256 = "dd89be148a8a9c4dd697df296403c00db302ed458fd93e89bcd83f452711478f";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/coding_agent_account_manager/releases/download/v${caamVersion}/caam_${caamVersion}_darwin_arm64.tar.gz";
              sha256 = "3863fb2ddfde51e4e6bded0498c933e0589487ae8a2211b216312840d242a205";
            };
          };
          caamSource = caamSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for caam: ${prev.stdenv.hostPlatform.system}");

          # agent-browser - browser automation CLI for AI agents
          agentBrowserVersion = "0.27.3";
          agentBrowserSources = {
            "x86_64-linux" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-linux-x64";
              sha256 = "0ls3fqvpf2p25jw47bvj6glsrpmqfq39zdsh59ph4p4i5w702grp";
            };
            "aarch64-linux" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-linux-arm64";
              sha256 = "0rakyqjy3jcs5ad5z1z3n8x6n1ssacmaf4d99mansxfh12a3dg1l";
            };
            "x86_64-darwin" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-darwin-x64";
              sha256 = "0bzms2c6wnpjrfswsw8pjp3rlhl5dc6qvm5jlx5ynvnv1pd82vhd";
            };
            "aarch64-darwin" = {
              url = "https://github.com/vercel-labs/agent-browser/releases/download/v${agentBrowserVersion}/agent-browser-darwin-arm64";
              sha256 = "08rp13knhz6v3x9jrq4rgaifa6nbh2h4r6pvv7fcm7gcx9wdv7jq";
            };
          };
          agentBrowserSource = agentBrowserSources.${prev.stdenv.hostPlatform.system} or (throw "Unsupported system for agent-browser: ${prev.stdenv.hostPlatform.system}");

          # pi - prompt injection detection agent (Rust)
          piVersion = "0.1.18";
          piSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/pi_agent_rust/releases/download/v${piVersion}/pi-linux-amd64.tar.xz";
              sha256 = "0ix87mphpa2bkcmpl6pryjxr69npb6g9k7r1av4l26bjfb02fkmi";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/pi_agent_rust/releases/download/v${piVersion}/pi-darwin-arm64.tar.xz";
              sha256 = "1sln14rrrsmmjqm6j9f2zqa09qmy303pzvcyr8pv4cs5x897d522";
            };
          };
          piSource = piSources.${prev.stdenv.hostPlatform.system} or null;

          # xf - cross-format file converter
          xfVersion = "0.3.2";
          xfSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/xf/releases/download/v${xfVersion}/xf-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "2f6820fb391ba36ff0c1920eff965a4db22040fbe353f05d071002a876fa507a";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/xf/releases/download/v${xfVersion}/xf-aarch64-apple-darwin.tar.gz";
              sha256 = "f3a6527091e0906b58e8b1b11fd5a2632293d22fcce1c50facb661aea3c9e697";
            };
          };
          xfSource = xfSources.${prev.stdenv.hostPlatform.system} or null;

          # mcp-agent-mail - Rust replacement for Python mcp_agent_mail
          mcpAgentMailVersion = "0.3.10";
          mcpAgentMailSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/v${mcpAgentMailVersion}/mcp-agent-mail-x86_64-unknown-linux-gnu.tar.xz";
              sha256 = "0mb7vb6n41q28kjsc6rn9qwd40bdrfrhbdfbsi0k3c05iqi7h82m";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/mcp_agent_mail_rust/releases/download/v${mcpAgentMailVersion}/mcp-agent-mail-aarch64-apple-darwin.tar.xz";
              sha256 = "0qa80027jax2fqscv6s8vmc2r5v9l9r9g28jfgikklj73kxgcpl7";
            };
          };
          mcpAgentMailSource = mcpAgentMailSources.${prev.stdenv.hostPlatform.system} or null;

          # casr - cross agent session resumer
          casrVersion = "0.1.1";
          casrSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/cross_agent_session_resumer/releases/download/v${casrVersion}/casr-x86_64-unknown-linux-musl.tar.xz";
              sha256 = "7ae074154c7de4febd1346f0173e155025e42c0c5c19ab72fc7fe3f68df984ec";
            };
            "aarch64-darwin" = {
              url = "https://github.com/Dicklesworthstone/cross_agent_session_resumer/releases/download/v${casrVersion}/casr-aarch64-apple-darwin.tar.xz";
              sha256 = "add7991d676f378804ff414384ea083d43bf375277de828d96bf3b8e7a309e4d";
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
          ptVersion = "2.1.0";
          ptSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/process_triage/releases/download/v${ptVersion}/pt-core-linux-x86_64-${ptVersion}.tar.gz";
              sha256 = "15xsyfhdr34wbpqqwv30nw57chms29s9abq8yrg0hd9c8c1wbn41";
            };
          };
          ptSource = ptSources.${prev.stdenv.hostPlatform.system} or null;

          # rch - remote compilation helper
          rchVersion = "1.0.41";
          rchSources = {
            "x86_64-linux" = {
              url = "https://github.com/Dicklesworthstone/remote_compilation_helper/releases/download/v${rchVersion}/rch-v${rchVersion}-x86_64-unknown-linux-gnu.tar.gz";
              sha256 = "17b94i6gmvam02pl83i4zn9f3f8sybhya10n5v3a7hq3sdx697r5";
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
            ubsVersion = "5.3.2";
            ubsBaseUrl = "https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/v${ubsVersion}";
            # Language modules (from v5.0.6 tag)
            ubsModules = {
              "ubs-js.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-js.sh"; sha256 = "0l8ma829ir8x4cymlgb0ary500f0qxqkl98043rkbjlhirhbqwnl"; };
              "ubs-python.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-python.sh"; sha256 = "1pjgz5svz8z1nr1bpnqf2sjndw2xpvkmyq5dmvw755aihm41n776"; };
              "ubs-cpp.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-cpp.sh"; sha256 = "01aqm3yq4cb74vqpbj6rcz5jq9rhaihd8669llgyhrmci5qvfm7h"; };
              "ubs-rust.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-rust.sh"; sha256 = "0h2p6ap0sb99ll86h60cwfrkrrbyb2z4shpddbw7xmyxs0irh916"; };
              "ubs-golang.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-golang.sh"; sha256 = "1smrpfqzfxald56q80qiggxy9ir1yrz8kqbj8yw7hlid7sa1qyjw"; };
              "ubs-java.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-java.sh"; sha256 = "18plk8k04y9cp2q31z1ivmq4khflf6x852i4jym0rhnpf79g4vcx"; };
              "ubs-ruby.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-ruby.sh"; sha256 = "0isl3hmbwi86wsbwq742gykaqq7lay349q7dj9lbn1frphd2awq9"; };
              "ubs-swift.sh" = prev.fetchurl { url = "${ubsBaseUrl}/modules/ubs-swift.sh"; sha256 = "1h79j7s5r1g9sf748l9jirhnsjscm9npwxann1fp7am7kzib5f5b"; };
            };
            # Helper assets (from v5.0.6 tag)
            ubsHelpers = {
              "helpers/resource_lifecycle_py.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_py.py"; sha256 = "0gj8034w6z8by725nwv1vsy4wcz2pmsq73wvkyhsd3wq5ks4z20y"; };
              "helpers/resource_lifecycle_go.go" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_go.go"; sha256 = "1g9q1qchpfaf1p9vzqahr7qh5mx9k5laaq4wgrd91mrdfwn5s88h"; };
              "helpers/resource_lifecycle_java.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/resource_lifecycle_java.py"; sha256 = "1w9rvy1bgygp4ysw3dwi5x4k1ajai2gzjigsyv6539za34axl1f0"; };
              "helpers/type_narrowing_ts.js" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_ts.js"; sha256 = "0ax3sc72d0xqzjjqfg3gmb76s2cnsvjif6qdnmdhd416rjh30vn2"; };
              "helpers/type_narrowing_rust.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_rust.py"; sha256 = "0zv422w0q6x8cshw7s72674i4il50lvvi70ncdy9myyzwq6dcnim"; };
              "helpers/type_narrowing_kotlin.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_kotlin.py"; sha256 = "0yddg1nai3f7cxi87vyic4jdvvlky6x5c2c3q9dd2jf3x21483vg"; };
              "helpers/type_narrowing_swift.py" = prev.fetchurl { url = "${ubsBaseUrl}/modules/helpers/type_narrowing_swift.py"; sha256 = "06ml047rqw5l77j1nddwp7mgzc0iriyx6xwwfzj6869rjbxbll7r"; };
            };
          in prev.stdenv.mkDerivation {
            pname = "ubs";
            version = ubsVersion;

            src = prev.fetchurl {
              url = "${ubsBaseUrl}/ubs";
              sha256 = "5a1765f05029e571e9d7da71ebb972b777e3ecbdafe540cdd17bd54eaf543132";
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
              # 0.1.18+ tarballs extract to a versioned subdir (pi-<ver>-<triple>/pi)
              cp pi-*/pi $out/bin/pi
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
            codexVersion = "0.142.5";
            codexSources = {
              "x86_64-linux" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-linux-x64.tgz";
                hash = "sha256-oD4xFssJCa67Az45zUAYs6Ha+dSJYxk5thY/+pB63kc=";
                vendorDir = "x86_64-unknown-linux-musl";
              };
              "aarch64-linux" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-linux-arm64.tgz";
                hash = "sha256-fsy6iZbom0h/6lKPTDe/UPDAoviSg2Z+aydKXnGbDUY=";
                vendorDir = "aarch64-unknown-linux-musl";
              };
              "x86_64-darwin" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-darwin-x64.tgz";
                hash = "sha256-8+8J7T5fMUCIghAQmnJeBQKSKzTaGKndAMVYHVAV1Pk=";
                vendorDir = "x86_64-apple-darwin";
              };
              "aarch64-darwin" = {
                url = "https://registry.npmjs.org/@openai/codex/-/codex-${codexVersion}-darwin-arm64.tgz";
                hash = "sha256-UfjbUXuToIbovKehCMrIGjE6buvPszNsoQW65J8Rd2w=";
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
            version = "0.46.0";

            src = prev.fetchzip {
              url = "https://github.com/google-gemini/gemini-cli/releases/download/v0.46.0/gemini-cli-bundle.zip";
              hash = "sha256-rUMVRWC++JWIcJ7Jil5yxo+3xreVeXQRK5DavbrLMeQ=";
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
