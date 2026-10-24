# Family Hermes agent on radon: the Telegram gateway, its config and secrets,
# and the cron run log (javdl/joost docs/plans/active/hermes-family-mac-mini.md,
# Milestone 4). Every path derives from agentRoot and hermesHome in
# hosts/radon.nix, so moving the state off the Agent volume is one edit there.
#
# Off until Joost has created secrets/radon.yaml with the five keys below and
# chosen where the state lives. With the gate off radon's system is unchanged.
{ agentRoot, hermesHome }:
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  enableHermesFamily = false;

  aperture = "https://ai.buri-hoki.ts.net/v1";
  cronRoute = {
    model = "spark/dsv41";
    model_provider = "aperture-local";
  };

  # The upstream module's own helpers, so the daemon starts the same command
  # line with the same environment as its gateway LaunchAgent would.
  hermesCommon = import "${inputs.hermes-agent}/nix/moduleCommon.nix" { inherit lib; };
  service = config.home-manager.users.hermes.services.hermes-agent;
  serviceEnvironment =
    hermesCommon.processEnvironment {
      inherit (service) hermesHome;
      managedSystem = "home-manager";
    }
    // {
      HOME = hermesHome;
      TMPDIR = "${agentRoot}/tmp";
      PATH = "${
        lib.makeBinPath (
          hermesCommon.processPath {
            inherit pkgs;
            cfg = service;
          }
        )
      }:/usr/bin:/bin:/usr/sbin:/sbin";
    };

  # launchd starts this at boot next to agent-volume-unlock. .env exists once
  # the volume is mounted and Home Manager has written the state, so wait for
  # it. Output is redirected only then: a StandardOutPath would be opened by
  # launchd before the volume is there.
  gatewayWrapper = pkgs.writeShellScript "hermes-gateway" ''
    set -eu
    waited=0
    while [ ! -e ${service.hermesHome}/.env ] && [ "$waited" -lt 120 ]; do
      /bin/sleep 1
      waited=$((waited + 1))
    done
    [ -e ${service.hermesHome}/.env ] || exit 1
    exec >>${agentRoot}/logs/hermes-gateway.log 2>&1
    ${lib.toShellVars serviceEnvironment}
    export ${toString (lib.attrNames serviceEnvironment)}
    cd ${service.workingDirectory}
    exec ${lib.escapeShellArgs (hermesCommon.gatewayArgv service)}
  '';

  runLogWrapper = pkgs.writeShellScript "hermes-run-log" ''
    set -eu
    [ -d ${service.hermesHome}/cron ] || exit 0
    exec >>${agentRoot}/logs/hermes-run-log.log 2>&1
    export TMPDIR=${agentRoot}/tmp
    exec ${pkgs.python3}/bin/python3 ${../../scripts/hermes-run-log.py} \
      --hermes-home ${service.hermesHome} \
      --run-log ${hermesHome}/runs.jsonl \
      --seen ${hermesHome}/state/run-log.seen \
      --cron-model ${cronRoute.model} \
      --cron-provider ${cronRoute.model_provider}
  '';
in
lib.mkIf enableHermesFamily {
  sops.secrets =
    lib.genAttrs
      [
        "hermes-env"
        "hermes-google-mail"
        "hermes-google-proposals"
        "hermes-google-read"
        "hermes-family"
      ]
      (_: {
        sopsFile = ../../secrets/radon.yaml;
        format = "yaml";
        owner = "hermes";
        mode = "0400";
      });

  # sops-nix installs secrets at the end of postActivation, after Home
  # Manager has merged hermes-env into .env (both append to postActivation,
  # sops with mkAfter). Install them before the launchd and user steps too.
  system.activationScripts.extraActivation.text = config.launchd.daemons.sops-install-secrets.command;

  home-manager.users.hermes = {
    imports = [ inputs.hermes-agent.homeManagerModules.default ];
    home.stateVersion = "26.05";
    # A service account: no agent CLIs, no Herdr or Moshi hooks, and no
    # moshi-hook LaunchAgent (users/agent-clis.nix).
    agentClis.enable = false;

    programs.hermes-agent.enable = true;
    services.hermes-agent = {
      enable = true;
      package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
      # Replaces the package's own group list, so messaging stays. The
      # anthropic SDK is an optional extra that aperture-claude's
      # anthropic_messages transport needs, and the store is read-only.
      extraDependencyGroups = [
        "messaging"
        "anthropic"
      ];
      # Its LaunchAgent would only run in a login session; the
      # hermes-gateway LaunchDaemon below runs it instead.
      gateway.enable = false;
      hermesHome = "${hermesHome}/.hermes";
      environmentFiles = [ config.sops.secrets.hermes-env.path ];
      settings = {
        timezone = "Europe/Amsterdam";
        providers = {
          aperture-claude = {
            base_url = aperture;
            api_mode = "anthropic_messages";
            key_env = "ANTHROPIC_API_KEY";
          };
          aperture-local = {
            base_url = aperture;
            api_mode = "chat_completions";
            models = [
              "spark/dsv41"
              "deepseek/deepseek-v4.1-flash"
            ];
          };
        };
        model = {
          provider = "aperture-local";
          default = "spark/dsv41";
        };
        # Hermes sends reasoning_effort "medium" by default, and dsv41
        # answers 400 to anything but low, high, xhigh, max or 1-100, so
        # every request fell back to the cloud model.
        agent.reasoning_overrides."spark/dsv41" = "high";
        cron = cronRoute;
        # dsv41 takes no images. An explicit vision backend makes Hermes
        # describe each photo with Claude and pass only the text on.
        auxiliary.vision = {
          provider = "aperture-claude";
          model = "claude-sonnet-5-5";
        };
        fallback_providers = [
          {
            provider = "aperture-local";
            model = "deepseek/deepseek-v4.1-flash";
          }
        ];
        # No approval-gated toolset (terminal, file, code_execution, browser,
        # computer_use, cronjob) on Telegram or in cron runs. no_mcp keeps
        # every MCP server off unless a cron job names one itself.
        platform_toolsets = {
          telegram = [
            "web"
            "vision"
            "skills"
            "todo"
            "no_mcp"
          ];
          cron = [
            "web"
            "skills"
            "todo"
            "no_mcp"
          ];
        };
        security.approval.transport_fallback = "deny";
      };
    };
  };

  launchd.daemons.hermes-gateway.serviceConfig = {
    ProgramArguments = [ "${gatewayWrapper}" ];
    UserName = "hermes";
    GroupName = "staff";
    RunAtLoad = true;
    KeepAlive = true;
  };

  launchd.daemons.hermes-run-log.serviceConfig = {
    ProgramArguments = [ "${runLogWrapper}" ];
    UserName = "hermes";
    GroupName = "staff";
    RunAtLoad = true;
    StartInterval = 300;
  };
}
