# Root-owned DGX Spark configuration, applied by Home Manager.
#
# DGX OS is Ubuntu, so nothing here is a NixOS module. Every activation runs
# one root script through `sudo -n` (the sudoers drop-in in docs/dgx-spark.md
# is the one manual prerequisite). The script compares each file below with
# /etc and rewrites only what differs, then runs that file's follow-up
# (daemon-reload, netplan apply, nmcli). A run with nothing to change touches
# nothing, so the nightly switch (users/home-auto-update.nix) also corrects
# drift.
#
# Managed: the NAS automount, the CX7 link (netplan on spark, NetworkManager
# on spark2), the OpenSSH fallback on 2222, and linger for joost.
# Left native: sudoers, apt, the NVIDIA driver and firmware, CUDA, Docker,
# tailscaled, locale.
{ currentSystemName }:

{
  lib,
  pkgs,
  ...
}:

let
  isSpark = currentSystemName == "spark";
  isSpark2 = currentSystemName == "spark2";
  enable = isSpark || isSpark2;

  # Files written into /etc: destination, mode, content, and what to run
  # after the file changed.
  etcFiles = [
    {
      path = "/etc/systemd/system/mnt-models.mount";
      mode = "0644";
      text = ''
        # Managed by nixos-config users/dgx-spark.nix.
        [Unit]
        Description=NAS model store
        After=network-online.target
        Wants=network-online.target

        [Mount]
        What=172.20.0.14:/mnt/tank/models
        Where=/mnt/models
        Type=nfs4
        Options=rw,noatime,nconnect=8,_netdev
      '';
      onChange = "daemon_reload=1";
    }
    {
      path = "/etc/systemd/system/mnt-models.automount";
      mode = "0644";
      text = ''
        # Managed by nixos-config users/dgx-spark.nix.
        [Unit]
        Description=Automount NAS model store

        [Automount]
        Where=/mnt/models
        TimeoutIdleSec=600

        [Install]
        WantedBy=remote-fs.target
      '';
      onChange = "daemon_reload=1";
    }
    # sshd and its socket keep the exact bytes already on both hosts, so the
    # first sync does not restart ssh.socket under a live session. On Ubuntu
    # 24.04 the socket's ports come from sshd_config through
    # sshd-socket-generator, so either file needs a daemon-reload and a socket
    # restart.
    {
      path = "/etc/ssh/sshd_config.d/50-fallback-2222.conf";
      mode = "0644";
      text = ''
        # Fallback when Tailscale SSH on 22 is unavailable. Key-only.
        Port 22
        Port 2222
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        PermitRootLogin no
      '';
      onChange = "daemon_reload=1; sshd_changed=1";
    }
    {
      path = "/etc/systemd/system/ssh.socket.d/50-fallback-2222.conf";
      mode = "0644";
      text = ''
        [Socket]
        ListenStream=0.0.0.0:2222
        ListenStream=[::]:2222
      '';
      onChange = "daemon_reload=1; sshd_changed=1";
    }
  ]
  ++ lib.optional isSpark {
    # The renderer is set per device. A top-level `renderer: networkd`
    # overrides 00-installer-config.yaml's global NetworkManager renderer;
    # NetworkManager then leaves every Ethernet device unmanaged and enP7s7
    # (the LAN) stays down after boot. That happened on 2026-10-26.
    path = "/etc/netplan/40-cx7.yaml";
    mode = "0600";
    text = ''
      network:
        version: 2
        ethernets:
          enp1s0f0np0:
            renderer: networkd
            dhcp4: false
            dhcp6: false
            link-local: []
            mtu: 9000
            addresses: [192.168.100.10/24]
          enP2p1s0f0np0:
            renderer: networkd
            dhcp4: false
            dhcp6: false
            link-local: []
            mtu: 9000
            addresses: [192.168.101.10/24]
    '';
    onChange = "netplan_changed=1";
  };

  # spark2 keeps its CX7 addresses in NetworkManager profiles (a networkd
  # netplan file there conflicted with NetworkManager). Values are the live
  # profiles of 2026-10-26, so the first sync changes nothing.
  nmProfiles = lib.optionals isSpark2 [
    {
      name = "Wired connection 1";
      settings = {
        "connection.interface-name" = "enp1s0f0np0";
        "ipv4.method" = "manual";
        "ipv4.addresses" = "192.168.100.11/24";
        "ipv4.gateway" = "";
        "ipv4.never-default" = "yes";
        "ipv6.method" = "auto";
        "802-3-ethernet.mtu" = "9000";
      };
    }
    {
      name = "Wired connection 4";
      settings = {
        "connection.interface-name" = "enP2p1s0f0np0";
        "ipv4.method" = "manual";
        "ipv4.addresses" = "192.168.101.11/24";
        "ipv4.gateway" = "";
        "ipv4.never-default" = "yes";
        "ipv6.method" = "auto";
        "802-3-ethernet.mtu" = "9000";
      };
    }
  ];

  syncFile = f: ''
    sync_file ${
      lib.escapeShellArgs [
        f.path
        f.mode
        (pkgs.writeText (baseNameOf f.path) f.text)
      ]
    } && { ${f.onChange}; }
  '';

  syncProfile =
    p:
    let
      fields = lib.concatStringsSep "," (lib.attrNames p.settings);
      want = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k}:${v}") p.settings);
      modArgs = lib.concatLists (
        lib.mapAttrsToList (k: v: [
          k
          v
        ]) p.settings
      );
    in
    ''
      name=${lib.escapeShellArg p.name}
      have=$("$nmcli" -t -f ${fields} connection show "$name" | sort)
      want=$(printf '%s\n' ${lib.escapeShellArg want} | sort)
      if [ "$have" != "$want" ]; then
        log "updating NetworkManager profile '$name'"
        "$nmcli" connection modify "$name" ${lib.escapeShellArgs modArgs}
        # An active link keeps its old settings until it is reactivated (next
        # boot or `nmcli connection up`). Bouncing it here would cut the RDMA
        # link of a running model.
        if "$nmcli" -t -f GENERAL.STATE connection show "$name" | grep -q activated; then
          log "'$name' is active: the change applies when it is next brought up"
        else
          "$nmcli" connection up "$name"
        fi
      fi
    '';

  rootSync = pkgs.writeShellScript "dgx-spark-root-sync" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.gnugrep
      ]
    }
    systemctl=/usr/bin/systemctl
    nmcli=/usr/bin/nmcli
    log() { echo "dgx-spark-root-sync: $*"; }

    # sync_file DEST MODE SOURCE: install SOURCE at DEST when the content or
    # mode differs. Returns 0 when it wrote the file.
    sync_file() {
      local dest=$1 mode=$2 src=$3
      if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$src" "$dest" \
        && [ "$(stat -c %a "$dest")" = "''${mode#0}" ]; then
        return 1
      fi
      log "writing $dest"
      # errexit does not apply inside a function called from `&&`: fail loudly.
      install -D -m "$mode" -o root -g root "$src" "$dest" || { log "cannot write $dest"; exit 1; }
    }

    daemon_reload=0 sshd_changed=0 netplan_changed=0
    ${lib.concatMapStrings syncFile etcFiles}

    if [ "$daemon_reload" = 1 ]; then "$systemctl" daemon-reload; fi
    if ! "$systemctl" is-enabled --quiet mnt-models.automount; then
      "$systemctl" enable --now mnt-models.automount
    fi
    if [ "$sshd_changed" = 1 ]; then
      /usr/sbin/sshd -t
      "$systemctl" restart ssh.socket
    fi
    if [ "$netplan_changed" = 1 ]; then
      /usr/sbin/netplan generate
      /usr/sbin/netplan apply
    fi
    ${lib.concatMapStrings syncProfile nmProfiles}
    if [ "$(/usr/bin/loginctl show-user joost -p Linger --value 2>/dev/null)" != yes ]; then
      log "enabling linger for joost"
      /usr/bin/loginctl enable-linger joost
    fi
  '';
in
{
  home.activation.dgxSparkRootSync = lib.mkIf enable (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ! /usr/bin/sudo -n true 2>/dev/null; then
        echo "dgx-spark-root-sync: passwordless sudo is missing; create /etc/sudoers.d/90-joost-nopasswd (docs/dgx-spark.md)" >&2
        exit 1
      fi
      $DRY_RUN_CMD /usr/bin/sudo -n ${rootSync}
    ''
  );
}
