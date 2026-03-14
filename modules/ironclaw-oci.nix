{ config, lib, pkgs, ... }:

let
  inherit (lib)
    attrValues
    filterAttrs
    foldl'
    literalExpression
    mapAttrs'
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    nameValuePair
    optionalAttrs
    recursiveUpdate
    types
    ;

  cfg = config.services.ironclawOci;

  containerStateDir = "/var/lib/ironclaw";
  containerAnthropicKeyPath = "/secrets/ironclaw-anthropic-api-key";
  containerTelegramTokenPath = "/secrets/ironclaw-telegram-bot-token";
  containerSlackBotTokenPath = "/secrets/ironclaw-slack-bot-token";
  containerSlackAppTokenPath = "/secrets/ironclaw-slack-app-token";
  containerSlackSigningSecretPath = "/secrets/ironclaw-slack-signing-secret";
  defaultSubordinateRangeSize = 65536;

  instanceType = types.submodule ({ name, config, ... }: {
    options = {
      enable = mkEnableOption "containerized IronClaw instance";

      package = mkOption {
        type = types.package;
        default = pkgs.ironclaw;
        description = "IronClaw package to include in the OCI image.";
      };

      user = mkOption {
        type = types.str;
        default = "ironclaw-${name}";
        description = "Dedicated host user running the rootless Podman container.";
      };

      group = mkOption {
        type = types.str;
        default = "ironclaw-${name}";
        description = "Dedicated host group running the rootless Podman container.";
      };

      uid = mkOption {
        type = types.int;
        description = "Static UID for the dedicated host user.";
      };

      gid = mkOption {
        type = types.int;
        default = config.services.ironclawOci.instances.${name}.uid;
        defaultText = literalExpression "config.services.ironclawOci.instances.<name>.uid";
        description = "Static GID for the dedicated host group.";
      };

      subUidStart = mkOption {
        type = types.int;
        description = "Start of the subordinate UID range for rootless Podman.";
      };

      subGidStart = mkOption {
        type = types.int;
        description = "Start of the subordinate GID range for rootless Podman.";
      };

      homeDir = mkOption {
        type = types.str;
        default = "/var/lib/ironclaw-containers/${name}/home";
        description = "Home directory for the dedicated host user.";
      };

      stateDir = mkOption {
        type = types.str;
        default = "/var/lib/ironclaw-containers/${name}/state";
        description = "Host state directory bind-mounted into the container.";
      };

      httpPort = mkOption {
        type = types.port;
        default = 3000;
        description = "Host loopback port mapped to the container HTTP port 3000.";
      };

      image = mkOption {
        type = types.str;
        default = "localhost/ironclaw-${name}:latest";
        description = "OCI image reference used for the rootless Podman container.";
      };

      databaseUrl = mkOption {
        type = types.str;
        description = "PostgreSQL connection string (e.g. postgres://ironclaw:pass@host/ironclaw).";
      };

      llmBackend = mkOption {
        type = types.str;
        default = "anthropic";
        description = "LLM backend provider (anthropic, openai, ollama, nearai, etc.).";
      };

      anthropicModel = mkOption {
        type = types.str;
        default = "claude-sonnet-4-20250514";
        description = "Anthropic model to use.";
      };

      anthropicKeyFile = mkOption {
        type = types.str;
        description = "Host path to the Anthropic API key file.";
      };

      telegramTokenFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Host path to the Telegram bot token file.";
      };

      slackBotTokenFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Host path to the Slack bot token file.";
      };

      slackAppTokenFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Host path to the Slack app token file.";
      };

      slackSigningSecretFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Host path to the Slack signing secret file.";
      };

      agentName = mkOption {
        type = types.str;
        default = "ironclaw-${name}";
        description = "Agent identifier for this instance.";
      };

      extraEnvironment = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Additional environment variables for the container.";
      };

      extraVolumes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional Podman bind mounts or volumes.";
      };

      extraOptions = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional podman run options for the container.";
      };
    };
  });

  enabledInstances = filterAttrs (_: inst: inst.enable) cfg.instances;

  mkEntrypoint = name: inst:
    pkgs.writeShellScriptBin "ironclaw-oci-entrypoint-${name}" ''
      set -euo pipefail

      anthropicKeyFile="${containerAnthropicKeyPath}"
      if [ ! -s "$anthropicKeyFile" ]; then
        echo "Missing or empty $anthropicKeyFile" >&2
        exit 1
      fi

      export ANTHROPIC_API_KEY="$(${pkgs.coreutils}/bin/tr -d '\n' < "$anthropicKeyFile")"
      export LLM_BACKEND="${inst.llmBackend}"
      export ANTHROPIC_MODEL="${inst.anthropicModel}"
      export DATABASE_URL="${inst.databaseUrl}"
      export AGENT_NAME="${inst.agentName}"
      export HOME="${containerStateDir}"
      export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      export HTTP_HOST="0.0.0.0"
      export HTTP_PORT="3000"
      export IRONCLAW_IN_DOCKER="true"

      # Telegram
      if [ -s "${containerTelegramTokenPath}" ]; then
        export TELEGRAM_BOT_TOKEN="$(${pkgs.coreutils}/bin/tr -d '\n' < "${containerTelegramTokenPath}")"
      fi

      # Slack
      if [ -s "${containerSlackBotTokenPath}" ]; then
        export SLACK_BOT_TOKEN="$(${pkgs.coreutils}/bin/tr -d '\n' < "${containerSlackBotTokenPath}")"
      fi
      if [ -s "${containerSlackAppTokenPath}" ]; then
        export SLACK_APP_TOKEN="$(${pkgs.coreutils}/bin/tr -d '\n' < "${containerSlackAppTokenPath}")"
      fi
      if [ -s "${containerSlackSigningSecretPath}" ]; then
        export SLACK_SIGNING_SECRET="$(${pkgs.coreutils}/bin/tr -d '\n' < "${containerSlackSigningSecretPath}")"
      fi

      ${pkgs.coreutils}/bin/mkdir -p "${containerStateDir}/data" "${containerStateDir}/logs"

      exec ${inst.package}/bin/ironclaw run --no-onboard
    '';

  mkImage = name: inst:
    let
      entrypoint = mkEntrypoint name inst;
    in
    pkgs.dockerTools.streamLayeredImage {
      name = "ironclaw-${name}";
      tag = "latest";
      contents = [
        pkgs.bash
        pkgs.cacert
        pkgs.coreutils
        entrypoint
        inst.package
      ];
      config = {
        Entrypoint = [ "${entrypoint}/bin/ironclaw-oci-entrypoint-${name}" ];
        Env = [
          "HOME=${containerStateDir}"
          "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          "IRONCLAW_IN_DOCKER=true"
        ];
        WorkingDir = containerStateDir;
      };
    };
in
{
  options.services.ironclawOci = {
    instances = mkOption {
      type = types.attrsOf instanceType;
      default = { };
      description = "Rootless Podman IronClaw instances built from Nix-generated OCI images.";
    };
  };

  config = mkIf (enabledInstances != { }) {
    virtualisation.oci-containers.backend = "podman";

    users.groups = mapAttrs' (_: inst: nameValuePair inst.group { gid = inst.gid; }) enabledInstances;

    users.users = mapAttrs' (_: inst: nameValuePair inst.user {
      isSystemUser = true;
      uid = inst.uid;
      group = inst.group;
      home = inst.homeDir;
      createHome = true;
      linger = true;
      shell = pkgs.bashInteractive;
      subUidRanges = [{
        startUid = inst.subUidStart;
        count = defaultSubordinateRangeSize;
      }];
      subGidRanges = [{
        startGid = inst.subGidStart;
        count = defaultSubordinateRangeSize;
      }];
    }) enabledInstances;

    systemd.tmpfiles.rules =
      builtins.concatLists (map
        (inst: [
          "d ${inst.homeDir} 0750 ${inst.user} ${inst.group} - -"
          "d ${inst.stateDir} 0750 ${inst.user} ${inst.group} - -"
          "d ${inst.stateDir}/data 0750 ${inst.user} ${inst.group} - -"
          "d ${inst.stateDir}/logs 0750 ${inst.user} ${inst.group} - -"
        ])
        (attrValues enabledInstances));

    virtualisation.oci-containers.containers = mapAttrs' (name: inst:
      let
        secretVolumes =
          (lib.optional (inst.telegramTokenFile != null)
            "${inst.telegramTokenFile}:${containerTelegramTokenPath}:ro")
          ++ (lib.optional (inst.slackBotTokenFile != null)
            "${inst.slackBotTokenFile}:${containerSlackBotTokenPath}:ro")
          ++ (lib.optional (inst.slackAppTokenFile != null)
            "${inst.slackAppTokenFile}:${containerSlackAppTokenPath}:ro")
          ++ (lib.optional (inst.slackSigningSecretFile != null)
            "${inst.slackSigningSecretFile}:${containerSlackSigningSecretPath}:ro");
      in
      nameValuePair "ironclaw-${name}" {
        image = inst.image;
        imageStream = mkImage name inst;
        pull = "never";
        autoStart = true;
        autoRemoveOnStop = true;
        log-driver = "journald";
        workdir = containerStateDir;
        hostname = "ironclaw-${name}";
        ports = [
          "127.0.0.1:${toString inst.httpPort}:3000"
        ];
        environment = {
          IRONCLAW_IN_DOCKER = "true";
          HOME = containerStateDir;
        } // inst.extraEnvironment;
        volumes = [
          "${inst.stateDir}:${containerStateDir}"
          "${inst.anthropicKeyFile}:${containerAnthropicKeyPath}:ro"
        ] ++ secretVolumes ++ inst.extraVolumes;
        extraOptions = [
          "--cap-drop=ALL"
          "--read-only"
          "--security-opt=no-new-privileges"
          "--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=256m,mode=1777"
          "--pids-limit=512"
          "--memory=2g"
          "--cpus=2"
          # Allow container to reach host PostgreSQL via localhost loopback
          "--network=slirp4netns:allow_host_loopback=true"
        ] ++ inst.extraOptions;
        podman = {
          user = inst.user;
          sdnotify = "container";
        };
      })
      enabledInstances;
  };
}
