{
  config,
  lib,
  pkgs,
  ...
}:

# Route coding-agent inference through Tailscale Aperture, the FashionUnited
# tailnet AI gateway (node `ai`, tag:aperture; the tailnet policy lets
# tag:devboxes reach it on tcp:80), so every request is attributed to the
# caller's tailnet identity and counted in Aperture's usage and logs (IT-297).
# See docs/aperture-agents.md for the per-agent mechanism and how to verify it
# on a host.
#
# Aperture passes each client's own credentials through: `anthropic-sub` takes
# the Claude subscription OAuth token or API key, `openai-sub` the ChatGPT
# login (it serves the ChatGPT backend, so platform API keys are rejected;
# hence no OPENAI_BASE_URL). OAuth login and token refresh still go to the
# vendors directly.
let
  cfg = config.services.apertureAgents;
  url = "http://${cfg.hostName}";

  # Codex reads /etc/codex/config.toml as its lowest-precedence layer, so a
  # user's own ~/.codex/config.toml keeps its model, trust state and MCP
  # servers and only inherits the provider. A user who sets model_provider
  # themselves opts out.
  codexConfig = (pkgs.formats.toml { }).generate "codex-aperture.toml" {
    model_provider = "aperture";
    model_providers.aperture = {
      name = "Aperture";
      base_url = "${url}/codex";
      wire_api = "responses";
      requires_openai_auth = true;
    };
  };

  # opencode merges $OPENCODE_CONFIG over the user's global config. Its
  # Anthropic SDK appends /messages to the base URL, so it needs the /v1
  # prefix that ANTHROPIC_BASE_URL must not carry for Claude Code.
  opencodeConfig = (pkgs.formats.json { }).generate "opencode-aperture.json" {
    "$schema" = "https://opencode.ai/config.json";
    provider.anthropic.options.baseURL = "${url}/v1";
  };

  # pi ignores ANTHROPIC_BASE_URL and omp needs its ChatGPT provider pointed
  # at Aperture, both through files the user also edits. Merge only the base
  # URLs into them on every switch rather than owning the files.
  agentConfig = pkgs.writeShellApplication {
    name = "aperture-agent-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.yq-go
    ];
    text = ''
      url=$1

      # Rewrite $file through the filter command; keep it untouched when the
      # result is identical, and never fail the caller's activation.
      merge() {
        local file=$1 tmp
        shift
        if [ -L "$file" ]; then
          echo "aperture: $file is a symlink, managed elsewhere; skipping" >&2
          return 0
        fi
        tmp=$(mktemp "$file.XXXXXX")
        if ! "$@" <"$file" >"$tmp"; then
          rm -f "$tmp"
          echo "aperture: could not update $file; skipping" >&2
          return 0
        fi
        if cmp -s "$tmp" "$file"; then
          rm -f "$tmp"
        else
          chmod --reference="$file" "$tmp"
          mv "$tmp" "$file"
          echo "aperture: pointed $file at $url"
        fi
      }

      mkdir -p "$HOME/.pi/agent"
      pi="$HOME/.pi/agent/models.json"
      [ -s "$pi" ] || echo '{}' >"$pi"
      # shellcheck disable=SC2016 # $u is a jq variable, not a shell one.
      merge "$pi" jq --arg u "$url" \
        '.providers.anthropic.baseUrl = $u | .providers["openai-codex"].baseUrl = $u'

      # omp migrates a legacy models.json only while no models.yml/.yaml
      # exists, so never create one next to it.
      omp_dir="$HOME/.omp/agent"
      if [ -e "$omp_dir/models.yaml" ] && [ ! -e "$omp_dir/models.yml" ]; then
        omp="$omp_dir/models.yaml"
      else
        omp="$omp_dir/models.yml"
      fi
      if [ ! -e "$omp" ] && [ -e "$omp_dir/models.json" ]; then
        echo "aperture: $omp_dir/models.json awaits omp's migration; skipping omp" >&2
        exit 0
      fi
      mkdir -p "$omp_dir"
      [ -s "$omp" ] || printf 'providers: {}\n' >"$omp"
      URL=$url merge "$omp" yq eval \
        '.providers.anthropic.baseUrl = strenv(URL) | .providers["openai-codex"].baseUrl = strenv(URL) | .providers style=""' -
    '';
  };
in
{
  options.services.apertureAgents = {
    enable = lib.mkEnableOption "routing coding agents through Tailscale Aperture";

    hostName = lib.mkOption {
      type = lib.types.str;
      default = "ai.stargazer-duck.ts.net";
      description = "MagicDNS name of the Aperture node.";
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "100.126.110.21";
      description = ''
        Tailnet address of the Aperture node, pinned in /etc/hosts because
        these hosts run tailscale with --accept-dns=false.
      '';
    };

    url = lib.mkOption {
      type = lib.types.str;
      default = url;
      readOnly = true;
      description = "Aperture base URL, for services that need it in their own environment.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Home-manager users whose pi and omp model configs get the Aperture
        base URL merged in on every switch. Leave out users whose dotfiles
        already own those files (chezmoi on joost's hosts).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    networking.hosts.${cfg.address} = [
      cfg.hostName
      "ai"
    ];

    # Claude Code and omp's Anthropic provider read this; Claude Code appends
    # /v1/messages itself.
    environment.variables = {
      ANTHROPIC_BASE_URL = url;
      OPENCODE_CONFIG = "${opencodeConfig}";
    };

    environment.etc."codex/config.toml".source = codexConfig;

    # Home Manager's own lib carries `hm.dag`; NixOS's does not.
    home-manager.users = lib.genAttrs cfg.users (
      _:
      { lib, ... }:
      {
        home.activation.apertureAgentConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD ${lib.getExe agentConfig} ${lib.escapeShellArg url}
        '';
      }
    );
  };
}
