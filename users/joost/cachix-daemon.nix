{
  config,
  lib,
  pkgs,
  ...
}:

# Per-user Cachix push daemon for joost's personal cache.
#
# Runs `cachix daemon run` as a per-user service:
#   - Linux  -> home-manager systemd user service
#   - Darwin -> home-manager launchd agent
#
# The daemon listens on a unix socket (see lib/cachix-push-hook.nix) and uploads
# store paths handed to it by the system nix `post-build-hook` (configured for
# Linux in modules/cachix.nix and for Darwin in hosts/mac-shared.nix). Only
# locally-built paths are pushed, and uploads happen asynchronously so they
# never block a build.
#
# Auth: cachix reads the token from ~/.config/cachix/cachix.dhall. The token is
# never in the Nix store. NOTE (2026-07-20): the chezmoi template this comment
# originally pointed at (dot_config/cachix/private_cachix.dhall.tmpl) never
# landed in the dotfiles repo — no machine has the file, so the daemon can't
# start anywhere. Provision the token per machine with `cachix authtoken <tok>`
# (from https://app.cachix.org/personal-auth-tokens), or add that template to
# dotfiles. Until the file exists the service skips via ExecCondition (clean
# "condition failed", no restart loop) and the matching .path unit starts the
# daemon automatically the moment the file appears.
#
# The cache's public key + substituter (the pull side) live in modules/cachix.nix.

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  cp = import ../../lib/cachix-push-hook.nix pkgs;
  cachix = "${pkgs.cachix}/bin/cachix";
  # --no-remote-stop: lifecycle is owned by the service manager; it stops the
  # daemon with SIGTERM, on which cachix flushes its queue gracefully.
  runArgs = [
    "daemon"
    "run"
    "--no-remote-stop"
    "--socket"
    cp.socket
    cp.cache
  ];
in
{
  systemd.user.services.cachix-daemon = lib.mkIf isLinux {
    Unit = {
      Description = "Cachix push daemon for ${cp.cache} (uploads locally-built paths)";
      After = [ "network.target" ];
    };
    Service = {
      Type = "simple";
      # Skipped-by-condition is not a failure, so Restart never fires while the
      # token is missing.
      ExecCondition = "${pkgs.coreutils}/bin/test -f %h/.config/cachix/cachix.dhall";
      ExecStart = "${cachix} ${lib.concatStringsSep " " runArgs}";
      Restart = "on-failure";
      RestartSec = 30;
      # Give the daemon time to flush its queue on stop.
      TimeoutStopSec = 120;
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.paths.cachix-daemon = lib.mkIf isLinux {
    Unit.Description = "Start cachix-daemon once its auth token is provisioned";
    Path.PathExists = "%h/.config/cachix/cachix.dhall";
    Install.WantedBy = [ "default.target" ];
  };

  launchd.agents.cachix-daemon = lib.mkIf isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ cachix ] ++ runArgs;
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/cachix-daemon.log";
      StandardErrorPath = "/tmp/cachix-daemon.log";
    };
  };
}
