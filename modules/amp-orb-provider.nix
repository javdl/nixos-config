# Amp self-hosted orb provider: this machine runs Amp orbs as Docker
# containers. `amp orb provider` connects out to ampcode.com, receives spawn,
# pause and delete jobs for one provider token, and runs the dispatch script
# below once per job (https://ampcode.com/docs/orbs/self-hosted).
#
# Setup per host: in Amp's Settings → Orbs, add an orb provider named after
# the host, add orb types with the names in `orbTypes`, and put the
# `aop_live_…` token in the host's sops file under `amp-orb-provider-token`.
# Runbook: fuww/fashionunited infra/nixos/docs/operations.md, "Amp Orb Provider".
#
# Docker keeps an orb's disk across a pause but not its memory, so a resumed
# orb runs `.agents/resume`. Archiving a thread pauses its orb and never
# deletes it; `amp-orb-reaper` removes orbs paused longer than
# `pausedOrbMaxDays` so they cannot fill the disk. Every container and
# snapshot image carries the label `ai.amp.orb=true`, which the disk cleanup
# jobs (lib/docker-prune-unmanaged.nix) leave alone.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ampOrbProvider;
  user = "amp-orb";
  home = "/var/lib/amp-orb";
  label = "ai.amp.orb=true";
  # A created, never started container that references the base image, so
  # the image prune (which drops every image no container uses) keeps it.
  imagePin = "amp-orb-image";

  orbTypeCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: type:
      "${lib.escapeShellArg name}) limits=(--cpus ${toString type.cpus} --memory ${lib.escapeShellArg type.memory}) ;;"
    ) cfg.orbTypes
  );

  dispatch = pkgs.writeShellApplication {
    name = "amp-orb-dispatch";
    runtimeInputs = [
      pkgs.docker
      pkgs.coreutils
    ];
    text = ''
      op="''${ORB_OPERATION:?}"
      id="''${ORB_ID:?}"
      exists() { docker container inspect "$id" >/dev/null 2>&1; }

      case "$op" in
        spawn)
          image="$ORB_IMAGE"
          if [ -n "''${ORB_SNAPSHOT_ID:-}" ] && docker image inspect "$ORB_SNAPSHOT_ID" >/dev/null 2>&1; then
            image="$ORB_SNAPSHOT_ID"
          fi
          orb_type="''${ORB_TYPE:-${cfg.defaultOrbType}}"
          case "$orb_type" in
            ${orbTypeCases}
            *)
              echo "orb type '$orb_type' is not in services.ampOrbProvider.orbTypes" >&2
              exit 1
              ;;
          esac
          if exists; then
            docker start "$id" >/dev/null
          else
            echo "creating $id from $image as $orb_type (''${limits[*]})"
            docker run --detach --init --name "$id" --label ${label} --shm-size 1g \
              "''${limits[@]}" "$image" sleep infinity >/dev/null
          fi
          # A bare --env NAME copies the value from this environment; an unset
          # AMP_URL is left out.
          docker exec --detach --env ORB_TOKEN --env AMP_URL "$id" amp orb bootstrap
          ;;
        pause)
          if exists; then
            docker stop "$id" >/dev/null
            if [ -n "''${ORB_SNAPSHOT_ID:-}" ]; then
              docker commit "$id" "$ORB_SNAPSHOT_ID" >/dev/null
              echo "saved snapshot $ORB_SNAPSHOT_ID"
            fi
          fi
          ;;
        delete)
          docker rm --force "$id" >/dev/null 2>&1 || true
          ;;
        *)
          echo "unknown ORB_OPERATION '$op'" >&2
          exit 1
          ;;
      esac
    '';
  };

  refreshImage = pkgs.writeShellApplication {
    name = "amp-orb-refresh-image";
    runtimeInputs = [ pkgs.docker ];
    text = ''
      # Offline is not fatal: the image already on disk still spawns orbs.
      docker pull --quiet ${lib.escapeShellArg cfg.image} || echo "could not pull ${cfg.image}; keeping the local copy" >&2
      docker rm --force ${imagePin} >/dev/null 2>&1 || true
      docker create --name ${imagePin} --label ${label} ${lib.escapeShellArg cfg.image} true >/dev/null
    '';
  };

  reaper = pkgs.writeShellApplication {
    name = "amp-orb-reaper";
    runtimeInputs = [
      pkgs.docker
      pkgs.coreutils
    ];
    text = ''
      cutoff=$(( $(date +%s) - ${toString cfg.pausedOrbMaxDays} * 86400 ))
      for id in $(docker ps --all --quiet --no-trunc --filter label=${label} --filter status=exited); do
        finished=$(docker inspect --format '{{.State.FinishedAt}}' "$id")
        if [ "$(date -d "$finished" +%s)" -lt "$cutoff" ]; then
          echo "removing $(docker inspect --format '{{.Name}}' "$id"), paused since $finished"
          docker rm "$id" >/dev/null
        fi
      done
      # Snapshot images no container uses; a thread that still needs one gets
      # a fresh orb from the base image instead.
      docker image prune --all --force --filter label=${label} --filter "until=$(( ${toString cfg.pausedOrbMaxDays} * 24 ))h" >/dev/null
    '';
  };

  orbType = lib.types.submodule {
    options = {
      cpus = lib.mkOption {
        type = lib.types.ints.positive;
        description = "CPUs the orb may use (`docker run --cpus`).";
      };
      memory = lib.mkOption {
        type = lib.types.str;
        description = "Memory limit of the orb (`docker run --memory`), such as \"8g\".";
      };
    };
  };
in
{
  options.services.ampOrbProvider = {
    enable = lib.mkEnableOption "running Amp orbs on this host as Docker containers";

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        File holding the provider's `aop_live_…` token from Amp's Settings →
        Orbs. Read as root at service start, so a sops secret owned by root
        works.
      '';
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "us-central1-docker.pkg.dev/amp-prod-0/amp-orb/amp-orb:latest";
      description = "Image new orbs start from when Amp passes no override. Pulled when the provider starts.";
    };

    orbTypes = lib.mkOption {
      type = lib.types.attrsOf orbType;
      default = {
        small = {
          cpus = 2;
          memory = "4g";
        };
        medium = {
          cpus = 4;
          memory = "8g";
        };
        large = {
          cpus = 8;
          memory = "16g";
        };
      };
      description = ''
        Resource limits per orb type. The names must match the orb types
        added to the provider in Amp's settings; a spawn for a name missing
        here fails.
      '';
    };

    defaultOrbType = lib.mkOption {
      type = lib.types.str;
      default = "medium";
      description = "Orb type used when Amp passes none, which happens while the provider has no orb types in Amp.";
    };

    pausedOrbMaxDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Remove orbs paused longer than this, and unused snapshot images older than this.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.orbTypes ? ${cfg.defaultOrbType};
        message = "services.ampOrbProvider.defaultOrbType must name an entry of services.ampOrbProvider.orbTypes";
      }
    ];

    virtualisation.docker.enable = true;

    users.groups.${user} = { };
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      extraGroups = [ "docker" ];
      inherit home;
      createHome = true;
    };

    systemd.services.amp-orb-provider = {
      description = "Amp self-hosted orb provider (Docker orbs on this host)";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "docker.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "docker.service" ];
      # The CLI writes its log under $HOME/.cache/amp. Amp passes ORB_IMAGE from
      # the provider's environment to every spawn job, its own default otherwise.
      environment = {
        HOME = home;
        ORB_IMAGE = cfg.image;
      };
      serviceConfig = {
        User = user;
        Group = user;
        LoadCredential = "token:${cfg.tokenFile}";
        ExecStartPre = lib.getExe refreshImage;
        # The first start pulls the 6 GB image.
        TimeoutStartSec = "20min";
        ExecStart = pkgs.writeShellScript "amp-orb-provider" ''
          AMP_ORB_PROVIDER_TOKEN="$(<"$CREDENTIALS_DIRECTORY/token")"
          export AMP_ORB_PROVIDER_TOKEN
          exec ${lib.getExe pkgs.amp-cli} orb provider ${lib.getExe dispatch}
        '';
        Restart = "always";
        RestartSec = 10;
      };
    };

    systemd.services.amp-orb-reaper = {
      description = "Remove Amp orbs paused longer than ${toString cfg.pausedOrbMaxDays} days";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe reaper;
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.amp-orb-reaper = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = 900;
        Persistent = true;
      };
    };
  };
}
