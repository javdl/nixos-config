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
  user = "rch";
  inherit (lib)
    mkEnableOption
    mkIf
    optionals
    ;
in
{
  options.services.rchWorker = {
    enable = mkEnableOption "rch remote-compilation worker support";
  };

  config = mkIf cfg.enable {
    # The worker's own rch-wkr, matching this host's nixpkgs (interpreter always
    # present) and GC-rooted because it's part of the system closure.
    environment.systemPackages = optionals (pkgs.remote-compilation-helper != null) [
      pkgs.remote-compilation-helper
    ];

    # Every rch client (bali from tag:devboxes, Amp orbs from tag:amp-orb in
    # the fashionunited.com tailnet policy) Tailscale SSHes in as this
    # account, which has no sudo or docker. All clients must share it: the
    # source-authority registry below is usable by one account only. zsh
    # reads /etc/zshenv even for `ssh host cmd`, which puts the per-user
    # profile's rustup and its cargo/rustc proxies ahead of the system cargo
    # and rustc.
    users.users.${user} = {
      isNormalUser = true;
      description = "rch remote builds";
      shell = pkgs.zsh;
      packages = [ pkgs.rustup ];
    };
    programs.zsh.enable = true;

    # A shell on a runner would otherwise reach everything the runner's
    # tag:github-runner identity may reach in the tailnet. Builds only need
    # the internet (crates.io); the SSH session itself is tailscaled's, not
    # this user's, so it is unaffected.
    networking.firewall.extraCommands = ''
      ip46tables -D OUTPUT -o tailscale0 -m owner --uid-owner ${user} -j REJECT 2>/dev/null || true
      ip46tables -I OUTPUT -o tailscale0 -m owner --uid-owner ${user} -j REJECT
    '';
    networking.firewall.extraStopCommands = ''
      iptables -w -D OUTPUT -o tailscale0 -m owner --uid-owner ${user} -j REJECT 2>/dev/null || true
      ip6tables -w -D OUTPUT -o tailscale0 -m owner --uid-owner ${user} -j REJECT 2>/dev/null || true
    '';

    # rch keeps a per-worker source-claim registry at the hardcoded
    # /tmp/rch-source-authority-locks, created umask 077 and coordinated with
    # flock, so only the account that created it can offload to this worker.
    # Claim it for ${user}: drop a copy another account created, and let
    # tmpfiles recreate it ${user}-owned. A trusted client that wants to
    # build here has to log in as ${user} too.
    system.activationScripts.rchSourceLocks = {
      deps = [ "users" ];
      text = ''
        rchLocks=/tmp/rch-source-authority-locks
        if [ -e "$rchLocks" ] && [ "$(stat -c %U "$rchLocks")" != ${user} ]; then
          rm -rf -- "$rchLocks"
        fi
      '';
    };

    systemd.tmpfiles.rules = [
      "d /tmp/rch-source-authority-locks 0700 ${user} users -"

      # rch canonical project root — rchd rsyncs the client project tree here.
      # Sticky and world-writable like /tmp, so accounts cannot touch each
      # other's mirrors.
      "d /data/projects 1777 root root -"
      "L+ /dp - - - - /data/projects"
      # Mirrors left by builds as another account (joost, before ${user} was
      # the only build account) cannot be replaced by ${user} under the sticky
      # bit, so rsync into them fails. Hand them to ${user}.
      "Z /data/projects/* - ${user} users -"

      # rch-wkr's remote base (transfer.remote_base, /data/tmp/rch in rch
      # 2.1.34) holds per-build recovery markers.
      "d /data/tmp/rch 0700 ${user} users -"
      # rch-wkr also uses fixed paths such as /tmp/rch-run (per-build process
      # records), /data/tmp/rch-sync and /data/tmp/rch-targets. Builds as
      # joost left them joost-owned, so ${user} builds failed with
      # "Permission denied". Hand every rch path in both roots to ${user}
      # instead of chasing them one at a time.
      "Z /tmp/rch* - ${user} users -"
      "Z /data/tmp/rch* - ${user} users -"

      # rchd runs `~/.local/bin/rch-wkr`; point it at the native (rooted) binary
      # so it survives reboots / Nix GC / a client nixpkgs bump. `L+` reasserts
      # the symlink even if `rch workers deploy-binary` previously dropped a
      # foreign binary there.
      "d /home/${user}/.local 0755 ${user} users -"
      "d /home/${user}/.local/bin 0755 ${user} users -"
      "L+ /home/${user}/.local/bin/rch-wkr - - - - /run/current-system/sw/bin/rch-wkr"

      # rchd pins the client's toolchain with `rustup run <channel> …` and
      # installs missing ones with `rch workers sync-toolchain` into
      # ~/.rustup (nixpkgs' rustup patchelfs them for NixOS). Only the rustup
      # binary goes in ~/.local/bin, so plain `cargo` stays the system one.
      # Cargo then calls `rustc` from PATH; `rustup run` puts ~/.cargo/bin
      # first, so the proxies there select the pinned rustc instead of the
      # system rustc. ~/.cargo/bin is not on this user's login PATH.
      "L+ /home/${user}/.local/bin/rustup - - - - ${pkgs.rustup}/bin/rustup"
      "d /home/${user}/.cargo 0755 ${user} users -"
      "d /home/${user}/.cargo/bin 0755 ${user} users -"
    ]
    ++ map (proxy: "L+ /home/${user}/.cargo/bin/${proxy} - - - - ${pkgs.rustup}/bin/rustup") [
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
