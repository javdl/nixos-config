{ config, lib, pkgs, ... }:

let
  inherit (lib)
    attrValues
    concatStringsSep
    filterAttrs
    foldl'
    hasPrefix
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

  cfg = config.services.openclawOci;

  deepConfigType = types.mkOptionType {
    name = "openclaw-oci-config";
    description = "OpenClaw JSON config (attrset), merged deeply via lib.recursiveUpdate.";
    check = builtins.isAttrs;
    merge = _loc: defs: foldl' recursiveUpdate { } (map (d: d.value) defs);
  };

  containerStateDir = "/var/lib/openclaw";
  containerConfigPath = "/etc/openclaw/openclaw.json";
  containerTelegramTokenPath = "/run/secrets/openclaw-telegram-bot-token";
  containerAnthropicKeyPath = "/run/secrets/openclaw-anthropic-api-key";
  containerGatewayTokenPath = "/run/secrets/openclaw-gateway-token";
  defaultSubordinateRangeSize = 65536;

  instanceType = types.submodule ({ name, config, ... }: {
    options = {
      enable = mkEnableOption "containerized OpenClaw instance";

      package = mkOption {
        type = types.package;
        default = pkgs.openclaw-gateway;
        description = "OpenClaw gateway package to include in the OCI image.";
      };

      user = mkOption {
        type = types.str;
        default = "openclaw-${name}";
        description = "Dedicated host user running the rootless Podman container.";
      };

      group = mkOption {
        type = types.str;
        default = "openclaw-${name}";
        description = "Dedicated host group running the rootless Podman container.";
      };

      uid = mkOption {
        type = types.int;
        description = "Static UID for the dedicated host user.";
      };

      gid = mkOption {
        type = types.int;
        default = config.services.openclawOci.instances.${name}.uid;
        defaultText = literalExpression "config.services.openclawOci.instances.<name>.uid";
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
        default = "/var/lib/openclaw-containers/${name}/home";
        description = "Home directory for the dedicated host user.";
      };

      stateDir = mkOption {
        type = types.str;
        default = "/var/lib/openclaw-containers/${name}/state";
        description = "Host state directory bind-mounted into the container.";
      };

      gatewayPort = mkOption {
        type = types.port;
        default = 18789;
        description = "Host loopback port mapped to the container gateway port 18789.";
      };

      browserPort = mkOption {
        type = types.port;
        default = 18791;
        description = "Host loopback port mapped to the container browser-control port 18791.";
      };

      image = mkOption {
        type = types.str;
        default = "localhost/openclaw-${name}:latest";
        description = "OCI image reference used for the rootless Podman container.";
      };

      telegramTokenFile = mkOption {
        type = types.str;
        description = "Host path to the Telegram bot token file.";
      };

      anthropicKeyFile = mkOption {
        type = types.str;
        description = "Host path to the Anthropic API key file.";
      };

      gatewayTokenFile = mkOption {
        type = types.str;
        description = "Host path to the OpenClaw gateway token file.";
      };

      allowFrom = mkOption {
        type = types.listOf (types.oneOf [ types.int types.str ]);
        default = [ ];
        description = "Telegram sender allowlist for this instance.";
      };

      allowTailscale = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the gateway should trust Tailscale peers for auth.";
      };

      extraConfig = mkOption {
        type = deepConfigType;
        default = { };
        description = "Additional OpenClaw JSON config merged into the generated base config.";
      };

      extraVolumes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional Podman bind mounts or volumes.";
      };

      extraEnvironment = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Additional environment variables for the container.";
      };

      extraOptions = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional `podman run` options for the container.";
      };
    };
  });

  enabledInstances = filterAttrs (_: inst: inst.enable) cfg.instances;

  mkOpenclawConfig = name: inst:
    let
      baseConfig = {
        agents.defaults.workspace = "${containerStateDir}/workspace";
        gateway = {
          mode = "local";
          auth = {
            mode = "token";
            allowTailscale = inst.allowTailscale;
          };
        };
        channels.telegram = {
          tokenFile = containerTelegramTokenPath;
          allowFrom = map toString inst.allowFrom;
        };
      };
    in
    pkgs.writeText "openclaw-oci-${name}.json" (builtins.toJSON (recursiveUpdate baseConfig inst.extraConfig));

  mkEntrypoint = name: inst:
    pkgs.writeShellScriptBin "openclaw-oci-entrypoint-${name}" ''
      set -euo pipefail

      tokenFile="${containerGatewayTokenPath}"
      anthropicKeyFile="${containerAnthropicKeyPath}"

      if [ ! -s "$tokenFile" ]; then
        echo "Missing or empty $tokenFile" >&2
        exit 1
      fi
      if [ ! -s "$anthropicKeyFile" ]; then
        echo "Missing or empty $anthropicKeyFile" >&2
        exit 1
      fi

      export OPENCLAW_GATEWAY_TOKEN="$(${pkgs.coreutils}/bin/tr -d '\n' < "$tokenFile")"
      export ANTHROPIC_API_KEY="$(${pkgs.coreutils}/bin/tr -d '\n' < "$anthropicKeyFile")"
      export HOME="${containerStateDir}"
      export OPENCLAW_NIX_MODE=1
      export OPENCLAW_CONFIG_PATH="${containerConfigPath}"
      export OPENCLAW_STATE_DIR="${containerStateDir}"
      export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

      ${pkgs.coreutils}/bin/mkdir -p "${containerStateDir}/workspace" "${containerStateDir}/logs" "${containerStateDir}/tmp"

      exec ${inst.package}/bin/openclaw gateway --port 18789
    '';

  mkImage = name: inst:
    let
      entrypoint = mkEntrypoint name inst;
    in
    pkgs.dockerTools.streamLayeredImage {
      name = "openclaw-${name}";
      tag = "latest";
      contents = [
        pkgs.bash
        pkgs.cacert
        pkgs.coreutils
        entrypoint
        inst.package
      ];
      config = {
        Entrypoint = [ "${entrypoint}/bin/openclaw-oci-entrypoint-${name}" ];
        Env = [
          "HOME=${containerStateDir}"
          "OPENCLAW_NIX_MODE=1"
          "OPENCLAW_CONFIG_PATH=${containerConfigPath}"
          "OPENCLAW_STATE_DIR=${containerStateDir}"
          "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        ];
        WorkingDir = containerStateDir;
      };
    };
in
{
  options.services.openclawOci = {
    instances = mkOption {
      type = types.attrsOf instanceType;
      default = { };
      description = "Rootless Podman OpenClaw gateway instances built from Nix-generated OCI images.";
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
          "d ${inst.stateDir}/workspace 0750 ${inst.user} ${inst.group} - -"
          "d ${inst.stateDir}/logs 0750 ${inst.user} ${inst.group} - -"
          "d ${inst.stateDir}/tmp 0750 ${inst.user} ${inst.group} - -"
        ])
        (attrValues enabledInstances));

    virtualisation.oci-containers.containers = mapAttrs' (name: inst:
      let
        configFile = mkOpenclawConfig name inst;
      in
      nameValuePair "openclaw-${name}" {
        image = inst.image;
        imageStream = mkImage name inst;
        pull = "never";
        autoStart = true;
        autoRemoveOnStop = true;
        log-driver = "journald";
        workdir = containerStateDir;
        hostname = "openclaw-${name}";
        ports = [
          "127.0.0.1:${toString inst.gatewayPort}:18789"
          "127.0.0.1:${toString inst.browserPort}:18791"
        ];
        environment = {
          OPENCLAW_CONFIG_PATH = containerConfigPath;
          OPENCLAW_STATE_DIR = containerStateDir;
          OPENCLAW_NIX_MODE = "1";
          HOME = containerStateDir;
          OPENCLAW_GATEWAY_TOKEN_FILE = containerGatewayTokenPath;
          ANTHROPIC_API_KEY_FILE = containerAnthropicKeyPath;
          TELEGRAM_BOT_TOKEN_FILE = containerTelegramTokenPath;
        } // inst.extraEnvironment;
        volumes = [
          "${inst.stateDir}:${containerStateDir}"
          "${configFile}:${containerConfigPath}:ro"
          "${inst.telegramTokenFile}:${containerTelegramTokenPath}:ro"
          "${inst.anthropicKeyFile}:${containerAnthropicKeyPath}:ro"
          "${inst.gatewayTokenFile}:${containerGatewayTokenPath}:ro"
        ] ++ inst.extraVolumes;
        extraOptions = [
          "--cap-drop=ALL"
          "--read-only"
          "--security-opt=no-new-privileges"
          "--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=256m,mode=1777"
          "--tmpfs=/run:rw,nosuid,nodev,size=64m"
          "--pids-limit=512"
          "--memory=2g"
          "--cpus=2"
        ] ++ inst.extraOptions;
        podman = {
          user = inst.user;
          sdnotify = "conmon";
        };
      })
      enabledInstances;
  };
}
