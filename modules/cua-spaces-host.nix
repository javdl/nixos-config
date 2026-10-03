# Cua Spaces host: this machine creates Linux Spaces (Docker containers) for
# the Cua Bots app and any other enrolled cua.ai device, over the cua.ai relay.
#
# The runtime is upstream's own: `cua host setup` writes ~/.cua/host (the
# relay machine token, policy and env token) and installs the systemd *user*
# unit cua-spacesd-host.service for the `cua` service account. Nix provides
# the binaries, the account, Docker, the cua daemon that creates the Spaces,
# and restarts after upgrades. Joining the relay needs one cua.ai device-code
# sign-in, so the first setup is a manual step per host:
#
#   sudo cua-spaces-host-setup
#
# See docs/cua-bots-fleet.md for the full runbook.
#
# Relay mode, not `--direct`: the controller Mac (radon) sits on a different
# tailnet than the tagged runner hosts, and tagged devices cannot be shared
# across tailnets. The relay is outbound WSS only, so no firewall port opens.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.cuaSpacesHost;
  user = "cua";
  home = "/var/lib/cua";
  # Stable paths that follow upgrades. The upstream unit runs
  # ~/.cua/host/bin/cua-spacesd, which tmpfiles points here.
  spacesdBin = "/run/current-system/sw/bin/cua-spacesd";

  setupScript = pkgs.writeShellApplication {
    name = "cua-spaces-host-setup";
    runtimeInputs = [
      pkgs.cua
      pkgs.sudo
      pkgs.coreutils
    ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "run as root: sudo cua-spaces-host-setup" >&2
        exit 1
      fi
      uid="$(id -u ${user})"
      as_cua() {
        sudo -u ${user} -H env \
          XDG_RUNTIME_DIR="/run/user/$uid" \
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
          "$@"
      }

      # A device code: approve it on a signed-in device or at the printed URL.
      as_cua cua auth login --remote --no-onboarding
      as_cua cua host setup \
        --profile spare \
        --name ${lib.escapeShellArg cfg.name} \
        --max-spaces ${toString cfg.maxSpaces} \
        --runner systemd \
        --driver-bin ${spacesdBin}
      # The host keeps only its machine token; drop the account session.
      as_cua cua auth logout
      as_cua cua host status
    '';
  };
in
{
  options.services.cuaSpacesHost = {
    enable = lib.mkEnableOption "providing Cua Spaces to cua.ai devices over the relay";

    name = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Display name on the relay; what `on: \"host:<name>\"` matches.";
    };

    maxSpaces = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 4;
      description = "Spaces this host runs at once (0: no limit). Applied by cua-spaces-host-setup.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    users.groups.${user} = { };
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      extraGroups = [ "docker" ];
      inherit home;
      createHome = true;
      shell = pkgs.bashInteractive;
      # The upstream unit runs in this account's user manager, which must run
      # without anyone logged in.
      linger = true;
    };

    environment.systemPackages = [
      pkgs.cua
      pkgs.cua-spacesd
      setupScript
    ];

    systemd.tmpfiles.rules = [
      "d ${home}/.cua 0700 ${user} ${user} - -"
      "d ${home}/.cua/host 0700 ${user} ${user} - -"
      "d ${home}/.cua/host/bin 0755 ${user} ${user} - -"
      # `cua host setup --driver-bin` copies the binary unless the destination
      # already resolves to it; this link keeps the unit on the current build.
      "L+ ${home}/.cua/host/bin/cua-spacesd - - - - ${spacesdBin}"
    ];

    # The daemon that creates and deletes the Spaces. cua-spacesd starts one
    # on demand from the store path recorded at setup time, which an upgrade
    # and GC leave dangling; running it here keeps the socket answering.
    systemd.user.services.cua-daemon = {
      description = "Cua daemon (creates the Spaces this host provides)";
      unitConfig.ConditionUser = user;
      wantedBy = [ "default.target" ];
      path = [ pkgs.docker ];
      serviceConfig = {
        # Keep the default loopback listener: env passthrough into Spaces
        # (agent API keys) refuses to work without it.
        ExecStart = "${pkgs.cua}/bin/cua daemon start --foreground";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # cua-spacesd-host.service is upstream's unit, written by setup, and its
    # ExecStart (the tmpfiles link) never changes, so switch-to-configuration
    # cannot see an upgrade. Restart it when the binary changes. (cua-daemon
    # is a NixOS unit; switch restarts it on its own.)
    systemd.services.cua-spacesd-host-restart = {
      description = "Restart the cua-spacesd user unit after an upgrade";
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ pkgs.cua-spacesd ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.systemd}/bin/systemctl --user -M ${user}@ try-restart cua-spacesd-host.service || true
      '';
    };
  };
}
