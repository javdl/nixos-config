# DGX Spark (`spark`, `spark2`)

Two NVIDIA DGX Sparks, managed the same way as the Omarchy boxes: a
standalone Home Manager output (`homeConfigurations`), not a NixOS host.
`mkSparkHome` in `flake.nix` builds both from
`users/joost/home-manager-spark.nix`. There is no system-manager input and
no other mechanism in this repo that writes `/etc` on non-NixOS Linux, so
the system files below are TODOs with the exact contents to keep. Do not
add a new system mechanism just for these two hosts.

| | `spark` | `spark2` |
|---|---|---|
| Output | `homeConfigurations.spark` | `homeConfigurations.spark2` |
| OS | DGX OS, Ubuntu 24.04, aarch64-linux | same |
| Hardware | GB10 Grace Blackwell, 128 GB unified memory | same |
| User | `joost`, uid/gid 1000 | same |
| Locale | `LANG=en_US.utf8` (`/etc/default/locale`, locale generated) | same |
| LAN | `enP7s7` `172.20.1.114/23`, gateway `172.20.0.1` | `enP7s7` `172.20.1.125/23`, gateway `172.20.0.1` |
| Tailnet | `spark.buri-hoki.ts.net`, Tailscale SSH on | `spark2.buri-hoki.ts.net`, Tailscale SSH on |
| CX7 renderer | netplan, `renderer: networkd`, `/etc/netplan/40-cx7.yaml` mode `600` | NetworkManager. Do not add a networkd netplan file: on this host it conflicted with NM and `netplan generate` crashed |

OpenSSH on both listens on 22 and 2222 (pubkey only, `PermitRootLogin no`).
This repo does not manage `sshd`.

## What Home Manager manages

User `joost` (`/home/joost`) only.

- Packages: `mosh`, `tmux`, `iperf3`, plus the headless CLI tools Quattro
  would have shipped from pacman (`bat`, `btop`, `eza`, `fd`, `fzf`, `jq`,
  `ripgrep`, `zoxide`) and a short list of headless tools the Omarchy Nix
  layer already installs (`curl`, `delta`, `gh`, `git`, `git-lfs`, `htop`,
  `rsync`, `tree`, `unzip`, `watch`, `wget`).
- `users/agent-clis.nix`, the same module `mkOmarchyHome` imports. That is
  where `herdr` comes from (the overlay package in `lib/overlays.nix`,
  currently 0.9.5), together with the agent CLIs and the `moshi-hook` user
  service. Desktop Omarchy extras are not installed: `tailmix`, `gollama`,
  `playerctl`, `thunderbird`, `insync`, browsers, fonts, NVIDIA Sync, Nsight.
- SSH client aliases, in `~/.ssh/config.d/dgx-spark-cx7`, included from the
  top of `~/.ssh/config` so the rest of that file is left in place:

  ```
  Host spark-cx7 192.168.100.10
    User joost
    IdentityFile ~/.ssh/id_ed25519_cx7
    IdentitiesOnly yes
    IdentityAgent none

  Host spark2-cx7 192.168.100.11
    User joost
    IdentityFile ~/.ssh/id_ed25519_cx7
    IdentitiesOnly yes
    IdentityAgent none
  ```

  `~/.ssh/id_ed25519_cx7` already exists on each box (ed25519, no passphrase,
  mode `600`, comment `spark-cx7` or `spark2-cx7`). The private key is not
  in this repo. Do not commit it.
- `~/.ssh/authorized_keys`: append only. Keys already published in
  `users/joost/nixos.nix` and `users/herdr-fleet-keys.nix` are added when
  the key blob is absent. Existing lines are not removed. The CX7 peer
  keys are not in the repo, so they are not added here. Each Spark accepts
  the other's CX7 key as a single line:

  ```
  from="192.168.100.0/24,192.168.101.0/24",no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAA... <comment>
  ```

  `<comment>` is `spark-cx7` on spark's key and `spark2-cx7` on spark2's
  key. The public halves are only on the boxes. Copying them into the repo
  is a separate change; until then a switch will not recreate these lines
  if they are deleted.

`users/joost/home-manager.nix` is not imported. That profile is the desktop,
and its chezmoi activation rewrites `~/.ssh/config`.

### herdr

The fleet inventory (`users/herdr-fleet.nix`) still runs
`/home/joost/.local/bin/herdr` on both Sparks. That is the 0.9.3 static
binary `scripts/bootstrap-herdr-node.sh` installed, and it is what the
lingering `herdr-agents` user unit execs. Home Manager puts the overlay
`herdr` on `PATH` via the Nix profile. Do not retarget `remoteBin` or the
unit at the Nix store path until the unit is deliberately cut over: the
controller and the running server have to stay on the same binary, and
replacing the unit restarts the `agents` session.

`~/.local/bin` is on `PATH` for Moshi's login shell. After the first
switch, check `which herdr`. If the Nix profile comes first, interactive
`herdr` is the overlay build while the user service is still 0.9.3.

## Apply

DGX OS is Ubuntu, so the Makefile takes the non-NixOS branch and uses Home
Manager, the same commands as Omarchy. On the Spark, as `joost`:

```bash
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

determinate-nixd login

make test NIXNAME=$(hostname -s)
make switch NIXNAME=$(hostname -s)
```

`hostname -s` is `spark` or `spark2`. The switch command `make` runs is:

```bash
nix run home-manager/release-26.05 -- switch -b backup --flake ".#spark"
```

(`.#spark2` on the other machine.) `-b backup` backs up files Home Manager
replaces. The activation does not replace `~/.ssh/config` or
`authorized_keys`.

`nix flake check` evaluates `homeConfigurations.spark` and `.spark2` on
x86_64-linux (every home configuration) and again on aarch64-linux
(`checks.aarch64-linux.eval-home-spark` and `eval-home-spark2`).

A switch installs and starts the `moshi-hook` user service from
`users/agent-clis.nix`. It does not touch the services in the next section.

## Do not manage or restart

- `spark-vllm` on spark (Docker vLLM serving Hermes on `:8888`, container
  `spark-qwen36-nvfp4`).
- Docker, the NVIDIA driver, and CUDA.
- The DGX OS updater and `dgx-dashboard` (`dgx-dashboard.service`,
  `dgx-dashboard-admin.service`, `/opt/nvidia/dgx-dashboard/dashboard-admin`).

The dashboard OTA check crashed spark's kernel once. Sequence, from the
journal on 2026-10-20: ConnectX-7 was hot-plugged, then
`dgx-dashboard-admin` ran
`python3 /opt/nvidia/spark-ota-check/check_ota_status.py is-ota-available`,
which ran `mstflint` as root. `mstflint` oopsed (`mstflint exited with irqs
disabled`, `mstflint_access` module loaded) and the kernel then soft-locked.
spark2 runs the same dashboard path and did not oops that day. Reboot
recovered spark. Nothing in this flake enables, disables, or restarts that
stack. Do not run `mstflint` against the CX7 after a hot-plug.

## System TODOs

No module in this repo owns these. They are the current desired contents.
Check them by hand; do not fold them into a NixOS configuration.

### NFS

`nfs-common` is required (`mount.nfs`). Both Sparks already have it
installed. `/etc/fstab` line, exactly:

```
172.20.0.14:/mnt/tank/models /mnt/models nfs4 rw,noatime,nconnect=8,_netdev,x-systemd.automount,x-systemd.idle-timeout=600 0 0
```

The mount point is `/mnt/models`. On spark this automount is in place
(`172.20.0.14:/mnt/tank/models`, nfs 4.2). spark2 had the fstab line and
the directory added separately. This repo does not write either.

### sudoers

`/etc/sudoers.d/90-joost-nopasswd`, mode `0440`:

```
joost ALL=(ALL) NOPASSWD:ALL
```

Install with `visudo -cf` on that file. spark2 has this file. spark was
still prompting for a password earlier the same day; confirm the file
there before assuming passwordless sudo works.

### ConnectX-7

One QSFP port, split by the GB10 into two netdevs. Addresses are
point-to-point, MTU 9000, no gateway, no DNS, never a default route.
`192.168.100.0/24` is `enp1s0f0np0`. `192.168.101.0/24` is
`enP2p1s0f0np0`. spark is `.10`, spark2 is `.11`.

`enp1s0f1np1` and `enP2p1s0f1np1` are the uncabled second port. Leave them
down.

**spark** uses netplan with networkd. `/etc/netplan/40-cx7.yaml`, mode
`600`:

```yaml
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
```

**spark2** uses NetworkManager. A networkd netplan file on this host
conflicted with NM and crashed `netplan generate`. Keep NM. The
connections are `Wired connection 1` (`enp1s0f0np0`) and
`Wired connection 4` (`enP2p1s0f0np0`):

```bash
sudo nmcli con mod "Wired connection 1" \
  ipv4.method manual \
  ipv4.addresses 192.168.100.11/24 \
  ipv4.gateway "" \
  ipv4.never-default yes \
  ipv6.method disabled \
  802-3-ethernet.mtu 9000
sudo nmcli con mod "Wired connection 4" \
  ipv4.method manual \
  ipv4.addresses 192.168.101.11/24 \
  ipv4.gateway "" \
  ipv4.never-default yes \
  ipv6.method disabled \
  802-3-ethernet.mtu 9000
sudo nmcli con up "Wired connection 1"
sudo nmcli con up "Wired connection 4"
```

Those settings persisted across spark2's reboot on 2026-10-20. Re-run them
only to repair the link. Do not write `/etc/netplan/40-cx7.yaml` on spark2.

After a CX7 hot-plug, spark2's DMA reads sat at about 13.5 Gb/s per
function until it was rebooted with the cable already in. A reboot cleared
it. That is separate from the `mstflint` oops above.

### apt

Desired packages (system packages, not a substitute for the Nix profile
copies of `mosh`, `tmux`, and `iperf3`):

```bash
sudo apt-get install -y mosh tmux nfs-common iperf3 perftest infiniband-diags
```

`perftest` provides `ib_write_bw`. As of 2026-10-21: `nfs-common`, `tmux`,
and `mosh` were installed on both; `ib_write_bw` was present on both;
`iperf3` was listening on spark and missing on spark2 (that box had iperf
2.1.9 only). `infiniband-diags` was not checked. This repo does not run
apt.

## Evaluation

```bash
nix eval --raw .#homeConfigurations.spark.activationPackage.drvPath
nix eval --raw .#homeConfigurations.spark2.activationPackage.drvPath
nix eval --raw .#checks.aarch64-linux.eval-home-spark
nix eval --raw .#checks.aarch64-linux.eval-home-spark2
```
