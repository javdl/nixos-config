{
  config,
  lib,
  pkgs,
  ...
}:

# Read-only fleet health probe for radon. A launchd user agent (the logged-in
# user, which on radon is joost) curls the personal-tailnet checks and writes
# one JSON file. It is not a LaunchDaemon, so it does not run as root, and it
# refuses the hermes account so it cannot see that user's secrets.
#
# The agent does not restart other jobs, open a port, or change Tailscale
# policy. spark:8443 may be dropped for tag:hermes; the probe records that
# instead of asking for an ACL edit. Nothing here dials the work tailnet.

let
  cfg = config.services.darwinFleetHealth;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.services.darwinFleetHealth = {
    enable = mkEnableOption "read-only fleet health probe";

    stateDir = mkOption {
      type = types.str;
      default = "/Users/joost/.local/state/radon-fleet-health";
      description = ''
        Directory for latest.json and the daily history. Owned by the
        logged-in user. Must not be on the Hermes Agent volume.
      '';
    };

    retentionDays = mkOption {
      type = types.ints.between 1 365;
      default = 14;
      description = "How many daily history files to keep, including today.";
    };

    intervalSeconds = mkOption {
      type = types.ints.between 60 86400;
      default = 900;
      description = "launchd StartInterval. 900 is every 15 minutes.";
    };

    owner = mkOption {
      type = types.str;
      default = "joost";
      description = "Account that owns the state directory. Not root or hermes.";
    };

    autoUpdateLog = mkOption {
      type = types.str;
      default = "/var/log/darwin-auto-update.log";
      description = "Log tailed for the last darwin-auto-update line. Read only.";
    };

    agentVolume = mkOption {
      type = types.str;
      default = "/Volumes/Agent";
      description = "Mount point checked via the mount table. Contents are not read.";
    };
  };

  config = mkIf (cfg.enable && pkgs.stdenv.isDarwin) (
    let
      probe = pkgs.writeShellScript "radon-fleet-health" ''
        set -eu
        umask 077
        case "$(/usr/bin/id -un)" in
          root|hermes)
            echo "radon-fleet-health: refusing to run as $(/usr/bin/id -un)" >&2
            exit 1
            ;;
        esac
        unset BW_SESSION ANTHROPIC_API_KEY OPENAI_API_KEY OPENROUTER_API_KEY \
          GH_TOKEN GITHUB_TOKEN HTTP_PROXY HTTPS_PROXY ALL_PROXY \
          http_proxy https_proxy all_proxy || true
        exec ${pkgs.python3}/bin/python3 ${../scripts/radon-fleet-health.py} \
          --state-dir ${lib.escapeShellArg cfg.stateDir} \
          --retention-days ${toString cfg.retentionDays} \
          --auto-update-log ${lib.escapeShellArg cfg.autoUpdateLog} \
          --agent-volume ${lib.escapeShellArg cfg.agentVolume} \
          --require-user ${lib.escapeShellArg cfg.owner}
      '';
    in
    {
      assertions = [
        {
          assertion = cfg.owner != "root" && cfg.owner != "hermes";
          message = "darwinFleetHealth.owner must be an unprivileged user other than hermes";
        }
        {
          assertion =
            lib.hasPrefix "/" cfg.stateDir
            && !lib.hasInfix " " cfg.stateDir
            && !lib.hasPrefix "/Volumes/Agent" cfg.stateDir;
          message = "darwinFleetHealth.stateDir must be an absolute path off the Agent volume";
        }
      ];

      # launchd opens StandardOutPath before the probe runs, so the directory
      # has to exist at switch. This only creates that directory.
      system.activationScripts.radonFleetHealth.text = ''
        /usr/bin/install -d -o ${cfg.owner} -g staff -m 0700 \
          ${cfg.stateDir} ${cfg.stateDir}/history
      '';

      launchd.user.agents.radon-fleet-health = {
        serviceConfig = {
          ProgramArguments = [ "${probe}" ];
          RunAtLoad = true;
          StartInterval = cfg.intervalSeconds;
          LowPriorityIO = true;
          Nice = 10;
          StandardOutPath = "${cfg.stateDir}/probe.log";
          StandardErrorPath = "${cfg.stateDir}/probe.log";
        };
      };
    }
  );
}
