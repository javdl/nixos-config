# DGX Spark (`spark`, `spark2`)

Two NVIDIA DGX Sparks. They are a **minimal** standalone Home Manager
profile, built by `mkSparkHome` in `flake.nix` from
`users/joost/home-manager-spark.nix`. They do not use `mkOmarchyHome`.

`homeConfigurations."spark"` and `."spark2"` are aarch64-linux.

| | `spark` | `spark2` |
|---|---|---|
| Output | `homeConfigurations.spark` | `homeConfigurations.spark2` |
| OS | DGX OS, Ubuntu 24.04, aarch64-linux | same |
| Hardware | GB10 Grace Blackwell, 128 GB unified memory | same |
| User | `joost`, uid/gid 1000 | same |
| Locale | `LANG=en_US.utf8` (native; this repo does not set it) | same |
| LAN | `enP7s7` `172.20.1.114/23`, gateway `172.20.0.1` | `enP7s7` `172.20.1.125/23`, gateway `172.20.0.1` |
| Tailnet | `spark.buri-hoki.ts.net`, Tailscale SSH on | `spark2.buri-hoki.ts.net`, Tailscale SSH on |
| CX7 renderer | netplan, `renderer: networkd` | NetworkManager. A networkd netplan file on this host conflicted with NM and crashed `netplan generate` |

OpenSSH on both listens on 22 and 2222 (pubkey only, `PermitRootLogin no`).
This repo does not manage `sshd`. `tailscaled` stays the DGX OS package.

Nix may not be installed yet. Use the same Determinate installer as Omarchy,
then `make test` / `make switch`. The Makefile takes the non-NixOS branch on
Ubuntu and runs Home Manager.

## What this profile contains

Nothing from the workstation or Omarchy package set. It does not import
`users/joost/home-manager.nix` or `users/agent-clis.nix`. No chezmoi, no
`omarchyExtraPackages`, no NVIDIA Sync, no Nsight, no desktop tools.

The entire managed set:

- Packages: `mosh`, `tmux`, `iperf3`, `herdr` (overlay in `lib/overlays.nix`).
- Herdr fleet node from `users/herdr-fleet.nix`: `herdr-agents` user service
  (`ExecStart` is the store path), `~/.config/herdr/fleet.toml`, and
  `HERDR_SESSION=agents`. Fleet `remoteBin` is
  `/home/joost/.nix-profile/bin/herdr`.
- `authorized_keys` activation, the same append fu137 uses. Controller lines
  from `users/herdr-fleet-keys.nix` are added when the full line is absent.
  Existing lines are not removed.
- Rendered files under `~/.config/dgx-spark/` (below). A switch does not
  copy them into `/etc`.
- The dsv41 cluster, one definition in `users/dsv41-cluster.nix`. spark
  runs `dsv41-cluster-head`. spark2 runs `dsv41-cluster-worker`. See
  [dsv41 cluster](#dsv41-cluster).

The Claude/Codex integration installer that other fleet nodes run is
disabled on the Sparks. A switch does not download Claude.

`scripts/bootstrap-herdr-node.sh` exits immediately on these hostnames.
The 0.9.3 binary it installs to `~/.local/bin` is the exe.dev pin. The
overlay is newer. Re-running the script would put the old unit back.

### SSH client aliases

This profile does not run chezmoi and does not write `~/.ssh/config`. The
hand-added CX7 aliases stay as they are. If they should be managed, the
follow-up is javdl/dotfiles, not this repo:

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

Each Spark accepts the other's CX7 key as one line. The public halves are
only on the boxes, so a switch will not recreate them:

```
from="192.168.100.0/24,192.168.101.0/24",no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAA... <comment>
```

`<comment>` is `spark-cx7` on spark's key and `spark2-cx7` on spark2's key.

### First switch

`-b backup` backs up files Home Manager replaces. Expect it to install the
four packages, write `~/.config/herdr/fleet.toml` and
`~/.config/dgx-spark/`, install and start `herdr-agents` (which restarts
the `agents` session if the bootstrap unit was already running), and append
bali and cmdpane keys if the exact line is missing.

Linger has to be on or the user service stops at logout:

```bash
loginctl show-user joost -p Linger
sudo loginctl enable-linger joost
```

Switch **spark and spark2 before bali** (and the command pane). Bali's
fleet config will point `remoteBin` at `~/.nix-profile/bin/herdr`. Bali
auto-updates from `main` at 04:00. If that lands first, the mirror misses
the binary until the Sparks have switched.

## One-time root install

Same precedent as tailmix: Home Manager renders the file, root installs it
once. `sudo` is required. The sudoers drop-in below is manual and is what
makes the rest non-interactive. None of these commands restart
`spark-vllm`, Docker, or `dgx-dashboard`.

### sudoers

Not rendered. Create it by hand and check the syntax:

```bash
sudo install -m 0440 /dev/null /etc/sudoers.d/90-joost-nopasswd
echo 'joost ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-joost-nopasswd >/dev/null
sudo chmod 0440 /etc/sudoers.d/90-joost-nopasswd
sudo visudo -cf /etc/sudoers.d/90-joost-nopasswd
```

spark2 already has this file (created 2026-10-21). spark was still
prompting earlier that day. Confirm before assuming passwordless sudo.

### NAS mount

`nfs-common` is already installed from apt on both hosts. This repo does
not install it. The rendered units are the systemd form of:

```
172.20.0.14:/mnt/tank/models /mnt/models nfs4 rw,noatime,nconnect=8,_netdev,x-systemd.automount,x-systemd.idle-timeout=600 0 0
```

If that fstab line is present, `systemd-fstab-generator` already owns
`mnt-models.mount` and `mnt-models.automount`. Remove or comment the line
before linking, or the two definitions fight.

```bash
sudo mkdir -p /mnt/models
# comment the /mnt/models line in /etc/fstab first, if it is there
sudo systemctl link ~/.config/dgx-spark/systemd/mnt-models.mount
sudo systemctl link ~/.config/dgx-spark/systemd/mnt-models.automount
sudo systemctl daemon-reload
sudo systemctl enable --now mnt-models.automount
```

Enable the automount, not the mount. If `systemctl link` refuses the
path, copy the resolved file into `/etc/systemd/system/` and daemon-reload,
same fallback as `docs/tailmix-omarchy.md`.

### ConnectX-7

One QSFP port, split by the GB10 into two netdevs. Addresses are
point-to-point, MTU 9000, no gateway, no DNS, never a default route.
`192.168.100.0/24` is `enp1s0f0np0`. `192.168.101.0/24` is
`enP2p1s0f0np0`. spark is `.10`, spark2 is `.11`.

`enp1s0f1np1` and `enP2p1s0f1np1` are the uncabled second port. Leave them
down.

**spark** — copy the rendered netplan and apply it. The file has no
gateway and does not mention `enP7s7`. `netplan apply` still reloads
networkd; run it from mosh or a console so a brief LAN blip does not drop
the session. Do not put this file on spark2.

```bash
sudo install -m 600 \
  ~/.config/dgx-spark/netplan/40-cx7.yaml \
  /etc/netplan/40-cx7.yaml
sudo netplan generate
sudo netplan apply
```

**spark2** — NetworkManager. The rendered script is the exact `nmcli`
invocations that were applied on 2026-10-20 (`Wired connection 1` on
`enp1s0f0np0`, `Wired connection 4` on `enP2p1s0f0np0`). Connection UUIDs
are not in the logs, so this is not an NM keyfile. `con up` bounces those
two connections, not the LAN, Docker, or `spark-vllm`.

```bash
~/.config/dgx-spark/apply-cx7.sh
```

After a CX7 hot-plug, spark2's DMA reads sat at about 13.5 Gb/s per
function until it was rebooted with the cable already in. A reboot cleared
it.

### Left native

Do not Nix-manage these. They are already the DGX OS / apt copies:

- NVIDIA driver, CUDA, `nvidia-container-toolkit`
- Docker
- `tailscaled`
- locale
- apt packages `mosh`, `tmux`, `nfs-common`, `iperf3`, `perftest`
  (`ib_write_bw`), `infiniband-diags`

The Nix profile still installs its own `mosh`, `tmux`, and `iperf3` for
the user PATH. That does not remove the apt copies. As of 2026-10-21,
`nfs-common`, `tmux`, and `mosh` were installed on both; `ib_write_bw` was
present on both; `iperf3` was listening on spark and missing on spark2
(that box had iperf 2.1.9 only).

## dsv41 cluster

One cluster, two ranks. The definition is `users/dsv41-cluster.nix`.
Changing the image digest, weights path, DSpark table, served name, port,
API key path, or the CX7 rendezvous is a one-line edit in that file and
applies to both machines. Each home imports it and runs the unit for its
own node:

| Node | Role | Unit | CX7 address | Declared RoCE GID |
|---|---|---|---|---|
| spark | head, rank 0 | `dsv41-cluster-head` | `192.168.100.10` | 3 |
| spark2 | worker, rank 1 | `dsv41-cluster-worker` | `192.168.100.11` | 5 |

The ranks pair on the CX7. The vLLM TCPStore and NCCL rendezvous is
`192.168.100.10:25000` (`rocep1s0f0` / `enp1s0f0np0`). The GID index is
detected at start from sysfs (RoCE v2 GID for that interface's IPv4,
indexes 0–15). The declared index is only the fallback. This path does
not follow the HTTP bind address.

There is one API endpoint, on the head. The default exposure is the
Aperture profile:

- Process bind `127.0.0.1:8000` on spark. Served model name `dsv41`.
- `GET /health` does not use an API key. `/v1/*`, including a 1-token
  chat, does.
- Tailscale Serve on spark: `tailscale serve --bg --https=8443
  http://127.0.0.1:8000`. Aperture base URL
  `https://spark.buri-hoki.ts.net:8443`.
- The key is `VLLM_API_KEY` in `~/.config/spark-vllm/api.env` on spark
  (mode `600`, not a symlink). It is passed into the container with
  `docker --env-file` and then as `vllm serve --api-key`. It is not in
  the repo or the Nix store.

`expose = "open"` in the cluster attrset is the previous listener:
`0.0.0.0:8000`, no key, and this module does not publish Tailscale Serve.
Set that in `users/dsv41-cluster.nix`, not in only one host. Switching to
`open` does not clear an existing Serve config.

The head also runs `dsv41-cluster-health.timer` (every 2 minutes, after
the head is active). The probe is a 1-token `POST /v1/chat/completions`
to `127.0.0.1:8000` with a 90 second timeout. In the Aperture profile the
probe sends the key. Two consecutive failures restart
`dsv41-cluster-head`. Probes while that unit is still activating are
ignored, so the measured ~6 minute load is not a failure.

The worker runs `dsv41-cluster-follow.timer` (every 30 seconds). It
restarts `dsv41-cluster-worker` only when the head goes from up to down.
In the Aperture profile the watch is a connect/close on
`192.168.100.10:25000`, because spark2 cannot open `127.0.0.1:8000` on
spark. In `open` mode the watch is `http://192.168.100.10:8000/health`
(no key). The first sample only records state.

`dsv41-cluster-head` sets `Conflicts=spark-vllm.service` and
`Conflicts=nvpair.service`. A user unit cannot stop a system unit, so
the head also refuses to start while either of those system units is
active. Stop and disable them before the switch. This module does not
enable, disable, or restart `spark-vllm`, `nvpair`, Docker, the driver,
or the DGX dashboard.

Tailnet ACLs are unchanged. They live in `javdl/joost`.

### Switch during a planned window

A switch replaces the hand-launched `dsv41-serve` containers. `docker rm
-f` runs before the new foreground `docker run --rm`. Do this while the
model can be down for the cold start (measured 6 minutes 23 seconds, plus
the switch itself).

On spark, before the switch, create the key file. Use the same value as
Aperture's provider API key. Do not commit it.

```bash
umask 077
install -d -m 700 ~/.config/spark-vllm
install -m 600 /dev/null ~/.config/spark-vllm/api.env
# one line, mode stays 600:
# VLLM_API_KEY=<the Aperture provider key>
```

Confirm on both machines: the pinned image is already local (`docker
image inspect` on the digest in `users/dsv41-cluster.nix`; the unit uses
`--pull=never`), `/home/joost/models/dsv41-1017-exl3` exists, `sudo -n
true` works, `loginctl show-user joost -p Linger` is `yes`, and `id -nG`
includes `docker`. On spark, `/usr/bin/tailscale` is the DGX OS binary.

Stop the radon launcher (`dsv41_tp2.sh` in tmux `dsv41`) so it does not
recreate the old containers.

Build first, then switch the worker and the head close together:

```bash
make test NIXNAME=spark2
make test NIXNAME=spark
make switch NIXNAME=spark2
make switch NIXNAME=spark
```

Watch `systemctl --user status dsv41-cluster-head` on spark. The unit
stays activating until `127.0.0.1:8000/v1/models` answers (the probe
sends the key). Then check `https://spark.buri-hoki.ts.net:8443/health`.

After this switch, clients of port 8000 on the LAN, the CX7, and the
tailnet stop working. That is the localhost bind. Use Aperture, or
`https://spark.buri-hoki.ts.net:8443`, with model name `dsv41`.

These failure modes were not tested on the hand-launched pair. The units
treat them as fail and restart (`Restart=always`, `RestartSec=30`,
`StartLimitBurst=5` per hour), but the underlying vLLM behavior is still
unknown:

- Worker-before-head: how long a headless worker keeps retrying
  `192.168.100.10:25000` if it starts minutes earlier.
- Head with no worker: how long the head waits for a missing rank.
- Peer death: the surviving rank may hang for up to 30 minutes
  (`VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=1800`) instead of exiting.

`systemctl --user reset-failed dsv41-cluster-head` clears the start
limit after that burst. The same command works for the worker unit.

### Roll back

Stop the units, then clear Tailscale Serve. The off command removes the
`:8443` publication; it does not restore the previous mapping to
`:8888`.

```bash
# spark
systemctl --user disable --now dsv41-cluster-head dsv41-cluster-serve dsv41-cluster-health.timer
tailscale serve --https=8443 off
# spark2
systemctl --user disable --now dsv41-cluster-worker dsv41-cluster-follow.timer
```

The next Home Manager switch enables `WantedBy` units again. A rollback
that should survive a switch sets `services.dsv41Cluster.enable = false`
in the shared profile and switches both hosts. To serve on every
interface again, set `expose = "open"` in `users/dsv41-cluster.nix` and
switch both hosts. Re-run `dsv41_tp2.sh up` only after the cluster units
are stopped, or the two will fight over the container name `dsv41-serve`.

## Do not manage or restart

- `spark-vllm` on spark (Docker vLLM serving Hermes on `:8888`, container
  `spark-qwen36-nvfp4`). It is not a service in this flake. The dsv41
  head refuses to start while `spark-vllm.service` or `nvpair.service`
  is active. Stop those system units before switching the cluster; this
  module does not do it.
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

## Apply

On the Spark, as `joost`. Skip the installer if `nix` is already on `PATH`.

```bash
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

determinate-nixd login

make test NIXNAME=spark
make switch NIXNAME=spark
```

Use `NIXNAME=spark2` on the other machine. `make test` builds
`.#homeConfigurations.$NIXNAME.activationPackage`. `make switch` runs:

```bash
nix run home-manager/release-26.05 -- switch -b backup --flake ".#spark"
```

## Evaluation

```bash
nix eval --raw .#homeConfigurations.spark.activationPackage.drvPath
nix eval --raw .#homeConfigurations.spark2.activationPackage.drvPath
nix eval --raw .#checks.aarch64-linux.eval-home-spark
nix eval --raw .#checks.aarch64-linux.eval-home-spark2
```
