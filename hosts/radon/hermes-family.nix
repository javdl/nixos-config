# Family Hermes agent on radon: the Signal gateway, its signal-cli daemon, the
# cron run log and the hermes-family command (javdl/joost
# docs/plans/active/hermes-family-mac-mini.md, Milestones 4 to 6). README:
# radon/hermes-family/README.md.
#
# The state lives on the Agent volume, and macOS lets a launchd job use that
# volume only through the Full Disk Access launcher (radon/agent-launcher.nix).
# The nightly darwin-auto-update activation is a launchd job too, so nothing
# here writes to the volume during activation and the hermes user has no Home
# Manager configuration. The gateway job does at each start what the upstream
# Home Manager activation would do: state directories, config.yaml, .env.
#
# Off until Joost has added the family keys to secrets/radon.yaml. With the
# gate off radon's system is unchanged.
{
  agentRoot,
  agentVolumeMounted,
  hermesHome,
}:
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
  # Free on radon (2026-10-25). signal-cli's default, 8080, is taken.
  signalCliPort = 18080;
  signalCliAddress = "127.0.0.1:${toString signalCliPort}";
  signalCliConfig = "${hermesHome}/signal-cli";
  hermesDir = "${hermesHome}/.hermes";
  logDir = "${agentRoot}/logs";
  tmpDir = "${agentRoot}/tmp";

  secret = name: config.sops.secrets.${name}.path;

  hermesCommon = import "${inputs.hermes-agent}/nix/moduleCommon.nix" { inherit lib; };

  # The upstream module's options, evaluated without Home Manager, so the
  # upstream helpers below get the record they expect.
  hermes =
    (lib.evalModules {
      modules = [
        {
          options = hermesCommon.sharedOptions {
            defaultPackage = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
            defaultPackageText = "hermes-agent.packages.\${system}.messaging";
            defaultWorkingDirectory = hermesHome;
            defaultWorkingDirectoryText = "hermesHome";
          };
        }
        {
          # Replaces the package's own group list, so messaging stays. The
          # anthropic SDK is an optional extra that aperture-claude's
          # anthropic_messages transport needs, mcp is the client for the
          # calendar servers, and the store is read-only.
          extraDependencyGroups = [
            "messaging"
            "anthropic"
            "mcp"
          ];
          environmentFiles = [ (secret "hermes-env") ];
          # Not a secret, so it comes from the store. The Signal adapter takes
          # its URL and account from the environment, and only when both are
          # set (plugins/platforms/signal/gateway_env.py:135-145).
          environment.SIGNAL_HTTP_URL = "http://${signalCliAddress}";
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
            # No approval-gated toolset (terminal, file, code_execution,
            # browser, computer_use, cronjob) on Signal or in cron runs.
            # no_mcp keeps every MCP server off unless a cron job names one.
            platform_toolsets = {
              signal = [
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
            # In the family group, answer only when mentioned
            # (gateway/config_loader.py:479-484).
            signal.require_mention = true;
            security.approval.transport_fallback = "deny";
          };
        }
      ];
    }).config;

  hermesPackage = hermesCommon.effectivePackage hermes;

  # The environment of every Hermes process here: the gateway and the
  # hermes-family command. The launcher passes only PATH.
  hermesEnvironment = hermesCommon.processEnvironment { hermesHome = hermesDir; } // {
    HOME = hermesHome;
    TMPDIR = tmpDir;
    PATH = "${
      lib.makeBinPath (
        hermesCommon.processPath {
          inherit pkgs;
          cfg = hermes;
        }
      )
    }:/usr/bin:/bin:/usr/sbin:/sbin";
  };

  # launchd starts the daemons at boot, before agent-volume-unlock has mounted
  # the volume and before sops-nix has installed the secrets. Until then a
  # daemon's output goes to its launch log in /var/log; after, to the volume.
  waitFor = name: condition: ''
    waited=0
    until ${agentVolumeMounted} && [ -d ${hermesHome} ] ${condition}; do
      if [ "$waited" -ge 120 ]; then
        echo "$(/bin/date -u +%FT%TZ) ${name}: ${hermesHome} not ready after 120 s" >&2
        exit 1
      fi
      /bin/sleep 1
      waited=$((waited + 1))
    done
    exec >>${logDir}/${name}.log 2>&1
  '';

  gatewayJob = pkgs.writeShellScript "hermes-gateway" ''
    set -eu
    ${waitFor "hermes-gateway" "&& [ -r ${secret "hermes-env"} ]"}
    ${lib.toShellVars hermesEnvironment}
    export ${toString (lib.attrNames hermesEnvironment)}
    umask 077
    ${hermesCommon.mkStateScript {
      inherit pkgs;
      cfg = hermes;
      hermesHome = hermesDir;
      inherit (hermes) workingDirectory;
      stateDirs = hermesCommon.stateSubdirs;
      modes = {
        config = "0600";
        env = "0600";
        managed = "0600";
        auth = "0600";
        document = "0600";
      };
    }}
    cd ${hermes.workingDirectory}
    exec ${lib.escapeShellArgs (hermesCommon.gatewayArgv hermes)}
  '';

  # Multi-account mode: Hermes names the account in every call and in the
  # events URL (plugins/platforms/signal/adapter.py:299, 563, 712), and
  # signal-cli 0.14.7 routes on it (HttpServerHandler.java:259-276,
  # SignalJsonRpcCommandHandler.java:66-72, 126-138). --no-receive-stdout keeps
  # message text out of the log.
  signalCliJob = pkgs.writeShellScript "hermes-signal-cli" ''
    set -eu
    ${waitFor "hermes-signal-cli" ""}
    export HOME=${hermesHome} TMPDIR=${tmpDir} JAVA_OPTS=-Djava.io.tmpdir=${tmpDir}
    umask 077
    exec ${pkgs.signal-cli}/bin/signal-cli --config ${signalCliConfig} \
      daemon --http ${signalCliAddress} --no-receive-stdout
  '';

  runLogJob = pkgs.writeShellScript "hermes-run-log" ''
    set -eu
    ${waitFor "hermes-run-log" ""}
    [ -d ${hermesDir}/cron ] || exit 0
    export TMPDIR=${tmpDir}
    umask 077
    exec ${pkgs.python3}/bin/python3 ${../../scripts/hermes-run-log.py} \
      --hermes-home ${hermesDir} \
      --run-log ${hermesHome}/runs.jsonl \
      --cron-model ${cronRoute.model} \
      --cron-provider ${cronRoute.model_provider}
  '';

  # The family Hermes for Joost's checks, for example `hermes-family config`
  # or `hermes-family cron list`: as hermes, with the gateway's environment.
  # Its HOME, HERMES_HOME and TMPDIR are on the Agent volume, so it refuses to
  # run unless the volume itself is mounted there, as the daemons wait for.
  hermesFamilyCommand = pkgs.writeShellScriptBin "hermes-family" ''
    if ! ${agentVolumeMounted}; then
      echo "hermes-family: the Agent volume is not mounted at ${agentRoot}" >&2
      exit 1
    fi
    cd /
    exec /usr/bin/sudo -u hermes -H /usr/bin/env ${
      lib.escapeShellArgs (lib.mapAttrsToList (name: value: "${name}=${value}") hermesEnvironment)
    } ${hermesPackage}/bin/hermes "$@"
  '';

  # Each runs as hermes through the launcher, which also makes their launch
  # logs in /var/log for hermes (radon/agent-launcher.nix).
  daemons = {
    hermes-gateway = {
      job = gatewayJob;
      serviceConfig.KeepAlive = true;
    };
    hermes-signal-cli = {
      job = signalCliJob;
      serviceConfig.KeepAlive = true;
    };
    hermes-run-log = {
      job = runLogJob;
      serviceConfig.StartInterval = 300;
    };
  };
  launchLog = name: "/var/log/${name}.launch.log";
in
lib.mkIf enableHermesFamily {
  sops.secrets.hermes-env = {
    sopsFile = ../../secrets/radon.yaml;
    format = "yaml";
    owner = "hermes";
    mode = "0400";
  };

  # Before the launchd step. sops-nix installs secrets only at the end of
  # postActivation, so a switch that changes a secret and the gateway job
  # would otherwise restart the gateway with the old secret.
  system.activationScripts.extraActivation.text = ''
    ${config.launchd.daemons.sops-install-secrets.command}
  '';

  environment.systemPackages = [ hermesFamilyCommand ];

  # signal-cli's HTTP API has no authentication: whoever reaches it can send
  # as the bot, so only hermes may. Merges into the anchor in hosts/radon.nix.
  environment.etc."pf.anchors/hermes".text = ''
    pass out quick on lo0 proto tcp from any to 127.0.0.1 port ${toString signalCliPort} user hermes
    block drop out quick on lo0 proto tcp from any to 127.0.0.1 port ${toString signalCliPort}
  '';

  agentLauncher.daemons = lib.mapAttrs (name: daemon: {
    inherit (daemon) job;
    serviceConfig = {
      UserName = "hermes";
      GroupName = "staff";
      RunAtLoad = true;
      StandardOutPath = launchLog name;
      StandardErrorPath = launchLog name;
    }
    // daemon.serviceConfig;
  }) daemons;
}
