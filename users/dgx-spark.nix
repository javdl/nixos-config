# Headless DGX Spark files that need root to install, plus radon's
# unattended SSH key.
#
# Home Manager only renders the root files under ~/.config/dgx-spark. The
# one-time root install is docs/dgx-spark.md, same pattern as tailmix on
# Omarchy (docs/tailmix-omarchy.md): Nix does not write /etc on these hosts.
#
# sudoers, apt, the NVIDIA driver, CUDA, Docker, tailscaled, and locale
# stay native. spark-vllm is not a service here.
#
# authorized_keys is append-only (lib/append-authorized-keys.nix). The
# Sparks also hold keys that are not in this repo (NVIDIA Sync,
# ssh-spark-joost-personal, the CX7 peer lines).
{ currentSystemName }:

{ lib, pkgs, ... }:

let
  isSpark = currentSystemName == "spark";
  isSpark2 = currentSystemName == "spark2";
  enable = isSpark || isSpark2;
  sparkKeys = import ./dgx-spark-keys.nix;
  appendAuthorizedKeys = import ../lib/append-authorized-keys.nix { inherit lib pkgs; };
in
{
  # Spark-only: enable is false for any other currentSystemName.
  home.activation.radonSparksAuthorizedKey = lib.mkIf enable (
    lib.hm.dag.entryAfter [ "writeBoundary" ] (appendAuthorizedKeys {
      keys = builtins.attrValues sparkKeys;
      label = "the radon-sparks key";
    })
  );

  home.file = lib.mkIf enable (
    {
      ".config/dgx-spark/systemd/mnt-models.mount".text = ''
        # Rendered by users/dgx-spark.nix. Link once as root; see docs/dgx-spark.md.
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

      ".config/dgx-spark/systemd/mnt-models.automount".text = ''
        # Rendered by users/dgx-spark.nix. Link once as root; see docs/dgx-spark.md.
        [Unit]
        Description=Automount NAS model store

        [Automount]
        Where=/mnt/models
        TimeoutIdleSec=600

        [Install]
        WantedBy=remote-fs.target
      '';
    }
    // lib.optionalAttrs isSpark {
      ".config/dgx-spark/netplan/40-cx7.yaml".text = ''
        network:
          version: 2
          renderer: networkd
          ethernets:
            enp1s0f0np0:
              dhcp4: false
              dhcp6: false
              link-local: []
              mtu: 9000
              addresses: [192.168.100.10/24]
            enP2p1s0f0np0:
              dhcp4: false
              dhcp6: false
              link-local: []
              mtu: 9000
              addresses: [192.168.101.10/24]
      '';
    }
    // lib.optionalAttrs isSpark2 {
      ".config/dgx-spark/apply-cx7.sh" = {
        executable = true;
        text = ''
          #!/bin/sh
          # Rendered by users/dgx-spark.nix. Run once as root; see docs/dgx-spark.md.
          # `con up` bounces these two ConnectX-7 connections only.
          set -eu
          if [ "$(id -u)" -ne 0 ]; then
            exec sudo "$0" "$@"
          fi
          nmcli con mod "Wired connection 1" \
            ipv4.method manual \
            ipv4.addresses 192.168.100.11/24 \
            ipv4.gateway "" \
            ipv4.never-default yes \
            ipv6.method disabled \
            802-3-ethernet.mtu 9000
          nmcli con mod "Wired connection 4" \
            ipv4.method manual \
            ipv4.addresses 192.168.101.11/24 \
            ipv4.gateway "" \
            ipv4.never-default yes \
            ipv6.method disabled \
            802-3-ethernet.mtu 9000
          nmcli con up "Wired connection 1"
          nmcli con up "Wired connection 4"
        '';
      };
    }
  );
}
