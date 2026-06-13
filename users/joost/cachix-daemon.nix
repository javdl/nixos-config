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
# Auth: cachix reads the token from ~/.config/cachix/cachix.dhall, rendered from
# Bitwarden by chezmoi (dot_config/cachix/private_cachix.dhall.tmpl). The token
# is never in the Nix store. Until that file exists (e.g. Bitwarden was locked
# at `chezmoi apply`) the daemon exits and the service retries.
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
      ExecStart = "${cachix} ${lib.concatStringsSep " " runArgs}";
      Restart = "on-failure";
      RestartSec = 30;
      # Give the daemon time to flush its queue on stop.
      TimeoutStopSec = 120;
    };
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
