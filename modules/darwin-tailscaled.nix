{ config, lib, pkgs, ... }:

# Hardened headless Tailscale for nix-darwin servers (argon, radon) —
# the macOS counterpart of services.tailscale on the Linux hosts.
#
# Why headless and not the GUI/macsys app:
#   - The macsys variant runs tailscaled in a sandbox, which refuses
#     `--ssh` ("does not run in sandboxed Tailscale GUI builds").
#   - The plain GUI cask's LaunchAgent runs tailscaled as the logged-in
#     user and exits because tailscaled needs root.
#
# What this module fixes vs. a bare launchd.daemons.tailscaled block:
#   --tun=userspace-networking  Required on macOS without macsys — third-party
#                               apps can't open kernel TUN devices, so without
#                               this flag tailscaled fails to set up networking.
#   --state / --statedir        Persistent state dir so auth survives reboots.
#   --operator                  Lets the named local user run `tailscale ...`
#                               without sudo (applied via auto-up).
#   authKeyFile + tailscaled-up Optional one-shot launchd job that runs
#                               `tailscale up --auth-key file:...` at boot, so
#                               the host reconnects unattended after reboots
#                               and rebuilds. `tailscale up` is idempotent on
#                               an already-authenticated daemon.

let
  cfg = config.services.darwinTailscaled;
  inherit (lib) mkEnableOption mkOption types mkIf mkMerge optionalString escapeShellArgs;
in {
  options.services.darwinTailscaled = {
    enable = mkEnableOption "hardened headless tailscaled launchd daemon";

    package = mkOption {
      type = types.str;
      default = "/opt/homebrew/opt/tailscale/bin/tailscaled";
      description = "Absolute path to the tailscaled binary (homebrew formula by default).";
    };

    cli = mkOption {
      type = types.str;
      default = "/opt/homebrew/opt/tailscale/bin/tailscale";
      description = "Absolute path to the tailscale CLI (used by the auto-up job).";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/tailscale";
      description = "Persistent state directory for tailscaled.";
    };

    socket = mkOption {
      type = types.str;
      default = "/var/run/tailscaled.socket";
      description = "Daemon socket path.";
    };

    port = mkOption {
      type = types.int;
      default = 41641;
      description = "WireGuard listening port.";
    };

    operator = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "joost";
      description = ''
        Local user that may run `tailscale ...` without sudo. Applied via
        `tailscale up --operator=...` when authKeyFile is set; for manual
        first-time `up`, pass `--operator=joost` yourself.
      '';
    };

    authKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/etc/tailscale/authkey";
      description = ''
        Path to a file containing a Tailscale auth key (generate at
        https://login.tailscale.com/admin/settings/keys; reusable + ephemeral
        is fine). When set, a one-shot launchd job runs `tailscale up
        --auth-key file:<path>` at boot so the host reconnects automatically
        after reboots/rebuilds. Place the file as root mode 0600. If the file
        is missing the auto-up job logs and exits without failing the daemon.
      '';
    };

    extraUpFlags = mkOption {
      type = types.listOf types.str;
      default = [ "--ssh" "--accept-routes" ];
      description = "Flags passed to `tailscale up` by the auto-up job.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      launchd.daemons.tailscaled = {
        script = ''
          # Ensure persistent state dir exists before tailscaled starts.
          mkdir -p ${cfg.stateDir}
          chmod 0700 ${cfg.stateDir}
          exec ${cfg.package} \
            --state=${cfg.stateDir}/tailscaled.state \
            --statedir=${cfg.stateDir} \
            --socket=${cfg.socket} \
            --port=${toString cfg.port} \
            --tun=userspace-networking
        '';
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "/var/log/tailscaled.log";
          StandardErrorPath = "/var/log/tailscaled.log";
        };
      };
    }

    (mkIf (cfg.authKeyFile != null) {
      launchd.daemons.tailscaled-up = {
        script = ''
          # Wait up to 30s for tailscaled to come up — launchd starts both
          # daemons in parallel and there's no native ordering between them.
          for _ in $(seq 1 30); do
            [ -S ${cfg.socket} ] && break
            sleep 1
          done
          if [ ! -r ${cfg.authKeyFile} ]; then
            echo "auth key file missing or unreadable: ${cfg.authKeyFile} — skipping auto-up"
            exit 0
          fi
          exec ${cfg.cli} --socket=${cfg.socket} up \
            --auth-key=file:${cfg.authKeyFile} \
            ${optionalString (cfg.operator != null) "--operator=${cfg.operator}"} \
            ${escapeShellArgs cfg.extraUpFlags}
        '';
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = false;
          StandardOutPath = "/var/log/tailscaled-up.log";
          StandardErrorPath = "/var/log/tailscaled-up.log";
        };
      };
    })
  ]);
}
