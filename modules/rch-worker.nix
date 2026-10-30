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
  orbUser = "rch";
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
        The SSH user trusted clients' rchd connects as (from workers.toml),
        such as bali's. Gets the ~/.local/bin/rch-wkr and rustup links.
      '';
    };
  };

  config = mkIf cfg.enable {
    # The worker's own rch-wkr, matching this host's nixpkgs (interpreter always
    # present) and GC-rooted because it's part of the system closure.
    environment.systemPackages = optionals (pkgs.remote-compilation-helper != null) [
      pkgs.remote-compilation-helper
    ];

    # Untrusted clients (Amp orbs, tag:amp-orb in the fashionunited.com
    # tailnet policy) Tailscale SSH in as this account instead of cfg.user,
    # who has passwordless sudo and docker. zsh reads /etc/zshenv even for
    # `ssh host cmd`, which puts the per-user profile's rustup and its
    # cargo/rustc proxies ahead of the system cargo and rustc.
    users.users.${orbUser} = {
      isNormalUser = true;
      description = "rch builds for Amp orbs";
      shell = pkgs.zsh;
      packages = [ pkgs.rustup ];
    };
    programs.zsh.enable = true;

    # A shell on a runner would otherwise reach everything the runner's
    # tag:github-runner identity may reach in the tailnet. Builds only need
    # the internet (crates.io); the SSH session itself is tailscaled's, not
    # this user's, so it is unaffected.
    networking.firewall.extraCommands = ''
      ip46tables -D OUTPUT -o tailscale0 -m owner --uid-owner ${orbUser} -j REJECT 2>/dev/null || true
      ip46tables -I OUTPUT -o tailscale0 -m owner --uid-owner ${orbUser} -j REJECT
    '';
    networking.firewall.extraStopCommands = ''
      iptables -w -D OUTPUT -o tailscale0 -m owner --uid-owner ${orbUser} -j REJECT 2>/dev/null || true
      ip6tables -w -D OUTPUT -o tailscale0 -m owner --uid-owner ${orbUser} -j REJECT 2>/dev/null || true
    '';

    systemd.tmpfiles.rules = [
      # rch canonical project root — rchd rsyncs the client project tree here.
      # Sticky and world-writable like /tmp: cfg.user and ${orbUser} each
      # create their own mirrors and cannot touch the other's.
      "d /data/projects 1777 root root -"
      "L+ /dp - - - - /data/projects"

      # rchd runs `~/.local/bin/rch-wkr`; point it at the native (rooted) binary
      # so it survives reboots / Nix GC / a client nixpkgs bump. `L+` reasserts
      # the symlink even if `rch workers deploy-binary` previously dropped a
      # foreign binary there.
      "d /home/${cfg.user}/.local 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.local/bin 0755 ${cfg.user} users -"
      "L+ /home/${cfg.user}/.local/bin/rch-wkr - - - - /run/current-system/sw/bin/rch-wkr"

      # rchd pins the client's toolchain with `rustup run <channel> …` and
      # installs missing ones with `rch workers sync-toolchain` into
      # ~/.rustup (nixpkgs' rustup patchelfs them for NixOS). Only the rustup
      # binary goes in ~/.local/bin, so plain `cargo` stays the system one.
      # Cargo then calls `rustc` from PATH; `rustup run` puts ~/.cargo/bin
      # first, so the proxies there select the pinned rustc instead of the
      # system rustc. ~/.cargo/bin is not on this user's login PATH.
      "L+ /home/${cfg.user}/.local/bin/rustup - - - - ${pkgs.rustup}/bin/rustup"
      "d /home/${cfg.user}/.cargo 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.cargo/bin 0755 ${cfg.user} users -"
    ]
    ++ map (proxy: "L+ /home/${cfg.user}/.cargo/bin/${proxy} - - - - ${pkgs.rustup}/bin/rustup") [
      "cargo"
      "rustc"
      "rustdoc"
      "cargo-clippy"
      "clippy-driver"
      "rustfmt"
      "cargo-fmt"
    ];
  };
}
