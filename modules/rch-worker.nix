{
  config,
  lib,
  pkgs,
  ...
}:

# rch (Remote Compilation Helper) WORKER support.
#
# A worker runs `rch-wkr` (invoked over SSH by the client's rchd) to execute
# offloaded build/test commands. On NixOS you can't just let the client scp its
# own rch-wkr: that binary's ELF interpreter is a nixpkgs-specific
# /nix/store/…-glibc/…/ld-linux path that may be absent on the worker (e.g. the
# client is on a newer nixpkgs), so it fails to exec with "no such file or
# directory". Fix declaratively: install the worker's OWN nix-built rch-wkr
# (bundled in remote-compilation-helper, built against THIS host's nixpkgs, so
# the interpreter always resolves and it's GC-rooted via the system closure) and
# point the path rchd invokes (~/.local/bin/rch-wkr) at it.
#
# Also provisions rch's canonical project root (/data/projects + the /dp alias),
# which rch requires the synced project tree to live under on the worker.

let
  cfg = config.services.rchWorker;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    optionals
    ;
in
{
  options.services.rchWorker = {
    enable = mkEnableOption "rch remote-compilation worker support";

    user = mkOption {
      type = types.str;
      default = "joost";
      description = ''
        The SSH user rchd connects as (from workers.toml). Owns /data/projects
        and the ~/.local/bin/rch-wkr symlink.
      '';
    };
  };

  config = mkIf cfg.enable {
    # The worker's own rch-wkr, matching this host's nixpkgs (interpreter always
    # present) and GC-rooted because it's part of the system closure.
    environment.systemPackages = optionals (pkgs.remote-compilation-helper != null) [
      pkgs.remote-compilation-helper
    ];

    systemd.tmpfiles.rules = [
      # rch canonical project root — rchd rsyncs the client project tree here.
      "d /data/projects 0755 ${cfg.user} users -"
      "L+ /dp - - - - /data/projects"

      # rchd runs `~/.local/bin/rch-wkr`; point it at the native (rooted) binary
      # so it survives reboots / Nix GC / a client nixpkgs bump. `L+` reasserts
      # the symlink even if `rch workers deploy-binary` previously dropped a
      # foreign binary there.
      "d /home/${cfg.user}/.local 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.local/bin 0755 ${cfg.user} users -"
      "L+ /home/${cfg.user}/.local/bin/rch-wkr - - - - /run/current-system/sw/bin/rch-wkr"
    ];
  };
}
