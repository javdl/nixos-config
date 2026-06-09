# Shared definition of joost's Cachix push setup, used by three consumers so
# the cache name and daemon socket path can never drift:
#   - modules/cachix.nix      (Linux nix.settings.post-build-hook, gated to joost)
#   - hosts/mac-shared.nix     (Darwin nix.custom.conf post-build-hook)
#   - users/joost/cachix-daemon.nix (the per-user `cachix daemon run` service)
#
# Model: a per-user `cachix daemon` (holding joost's auth token from
# ~/.config/cachix/cachix.dhall) listens on `socket`. The system post-build-hook
# runs as root after every build and hands the just-built $OUT_PATHS to the
# daemon, which uploads them asynchronously. Only locally-BUILT paths are pushed
# (unlike `watch-store`, which also re-uploaded substituted paths).
#
# The hook is best-effort: if the daemon is down or the socket is missing it
# fails fast and `|| true` keeps the build green.

pkgs:
let
  cache = "javdl-nixos-config";
  # Fixed absolute path so the user daemon and the root post-build-hook agree
  # without per-UID runtime-dir lookups. Short enough for the macOS sun_path limit.
  socket = "/tmp/cachix-daemon.sock";
in
{
  inherit cache socket;

  hook = pkgs.writeShellScript "cachix-daemon-push" ''
    set -f            # disable globbing; $OUT_PATHS is a plain space list
    export IFS=' '
    ${pkgs.cachix}/bin/cachix daemon push --socket ${socket} $OUT_PATHS 2>/dev/null || true
  '';
}
