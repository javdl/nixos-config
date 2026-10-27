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
| CX7 renderer | netplan, per-device `renderer: networkd` | NetworkManager profiles. A networkd netplan file on this host conflicted with NM and crashed `netplan generate` |

OpenSSH on both listens on 22 and 2222 (pubkey only, `PermitRootLogin no`),
from files this repo syncs into `/etc`. `tailscaled` stays the DGX OS package.

Nix may not be installed yet. Use the same Determinate installer as Omarchy,
then `make test` / `make switch`. The Makefile takes the non-NixOS branch on
Ubuntu and runs Home Manager. After the first switch both hosts update
themselves nightly ([Nightly update](#nightly-update)).

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
- Root-owned files synced into `/etc` on every activation by
  `users/dgx-spark.nix` ([below](#root-owned-configuration)).
- `home-auto-update.timer`: the nightly switch from GitHub. See
  [Nightly update](#nightly-update).
- The production model, Mia TensorFold, as `dsv41-mia.service` on spark.
  spark2 has no model unit. Tailscale Serve stays `dsv41-cluster-serve`.
  The sybil EXL3 head and worker are installed only when
  `services.dsv41Cluster.enable` is set back to true. See [dsv41](#dsv41).

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
four packages, write `~/.config/herdr/fleet.toml`, install and start
`herdr-agents` (which restarts the `agents` session if the bootstrap unit
was already running), append bali and cmdpane keys if the exact line is
missing, and run the root sync below. The sudoers drop-in has to exist
first: without passwordless sudo the activation stops with an error.

Switch **spark and spark2 before bali** (and the command pane). Bali's
fleet config will point `remoteBin` at `~/.nix-profile/bin/herdr`. Bali
auto-updates from `main` at 04:00. If that lands first, the mirror misses
the binary until the Sparks have switched.

## Root-owned configuration

`users/dgx-spark.nix` adds an activation step that runs one script as root
(`sudo -n`) on every switch, including the nightly one. The script compares
each managed file with `/etc` and rewrites only the ones whose content or
mode differ, then runs that file's follow-up. A run with nothing to change
touches nothing, so it is safe to repeat and it corrects drift overnight.
None of it restarts Docker, `dgx-dashboard`, or a running model.

| File or setting | Host | After a change |
|---|---|---|
| `/etc/systemd/system/mnt-models.{mount,automount}` (NAS `172.20.0.14:/mnt/tank/models` on `/mnt/models`) | both | `daemon-reload`; the automount is enabled if it is not |
| `/etc/ssh/sshd_config.d/50-fallback-2222.conf`, `/etc/systemd/system/ssh.socket.d/50-fallback-2222.conf` | both | `daemon-reload`, `sshd -t`, restart `ssh.socket` |
| `/etc/netplan/40-cx7.yaml` | spark | `netplan generate`, `netplan apply` |
| NetworkManager profiles `Wired connection 1` and `4` | spark2 | `nmcli connection modify`; the link is brought up only if it is not already active |
| Linger for `joost` | both | `loginctl enable-linger joost` |

Edit the files in `users/dgx-spark.nix`, not in `/etc`: the next switch
puts the managed copy back.

### sudoers

The one manual prerequisite. Create it by hand and check the syntax:

```bash
sudo install -m 0440 /dev/null /etc/sudoers.d/90-joost-nopasswd
echo 'joost ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-joost-nopasswd >/dev/null
sudo chmod 0440 /etc/sudoers.d/90-joost-nopasswd
sudo visudo -cf /etc/sudoers.d/90-joost-nopasswd
```

Both hosts have it.

### NAS mount

`nfs-common` comes from apt on both hosts. The units are the systemd form
of this fstab line, which is commented out in `/etc/fstab` on both hosts:

```
172.20.0.14:/mnt/tank/models /mnt/models nfs4 rw,noatime,nconnect=8,_netdev,x-systemd.automount,x-systemd.idle-timeout=600 0 0
```

If that line is active, `systemd-fstab-generator` also defines
`mnt-models.mount` and the two definitions fight. Keep it commented.

### ConnectX-7

One QSFP port, split by the GB10 into two netdevs. Addresses are
point-to-point, MTU 9000, no gateway, no DNS, never a default route.
`192.168.100.0/24` is `enp1s0f0np0`. `192.168.101.0/24` is
`enP2p1s0f0np0`. spark is `.10`, spark2 is `.11`.

`enp1s0f1np1` and `enP2p1s0f1np1` are the uncabled second port. Leave them
down.

**spark** uses netplan. The file sets `renderer: networkd` per device,
never at the top level: a top-level renderer overrides
`00-installer-config.yaml`'s global `NetworkManager`, NetworkManager then
leaves every Ethernet device unmanaged, and `enP7s7` stays down after the
next boot (no LAN, no tailnet; happened 2026-10-26). `netplan apply`
reloads networkd, so a change to this file blips the CX7 link.

**spark2** uses NetworkManager profiles. The sync modifies a profile whose
settings differ, but does not reactivate a link that is up: bouncing it
would cut the RDMA link of a running model. The change applies at the next
boot or `nmcli connection up`.

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
the user PATH. That does not remove the apt copies.

Firmware (SoC, EC, USB-C PD, CX7) comes from `fwupdmgr`, not apt. On
2026-10-26 spark ran the 7.6.0 driver on older SoC and EC firmware, and its
GPU failed about 3 minutes after every boot (Xid 119 GSP timeouts, `bad
register read`, `nvidia-smi` showing `ERR!`). `sudo fwupdmgr update` to
the versions in NVIDIA's release notes fixed it. After a DGX OS update,
check `fwupdmgr get-updates` too.

## Nightly update

`users/home-auto-update.nix` installs `home-auto-update.timer` on both
hosts: 04:00 plus up to an hour of random delay, `Persistent=true` so a
missed run happens at the next boot. Same schedule as radon
(`services.darwinAutoUpdate`) and the NixOS servers.

The run builds
`github:javdl/nixos-config#homeConfigurations.<host>.activationPackage`
from `main` as it is at that moment, points the Home Manager profile at it
when it changed, and runs its activation. Activation runs even when the
generation is unchanged, so the root sync above re-checks `/etc` every
night. A change reaches the Sparks by merging to `main`. A change to
`dsv41-mia.service` restarts the model on that run (a cold load of a few
minutes).

```bash
systemctl --user list-timers home-auto-update.timer
systemctl --user start home-auto-update     # run it now
journalctl --user -u home-auto-update
```

The unit carries `X-SwitchMethod=keep-old`, so the activation it runs does
not restart it halfway through.

## dsv41

The production model on the two Sparks is Mia-AiLab DeepSeek V4.1 Flash
1017 EAQ 2.9bpw on TensorFold. Joost approved that swap on 26 Oct 2026.
One measured run that day, four streams sustained, was 150.5 tok/s against
126.2 tok/s for the sybil EXL3 server it replaced. A warm start reached
`/health` in 209 seconds.

There is still one API, on spark:

| | |
|---|---|
| Served name | `dsv41` |
| Process bind | `127.0.0.1:8000` on spark |
| Tailscale | `dsv41-cluster-serve` on spark: `https://spark.buri-hoki.ts.net:8443` to that port |
| Key | Required on `/v1/*`. `GET /health` does not use it |
| Context | 262144 tokens, 4 streams, DSpark drafts on |
| Engine | TensorFold, image `tensorfold-dsv41:exl3-tp2-625d420e24a4` |
| Weights | NAS paths under `/mnt/models/mia29`, named in the recipe's `scripts/local.sh` |

`dsv41-cluster-serve` is unchanged. It is still the oneshot in
`users/dsv41-cluster.nix` (`tailscale serve --bg --https=8443
http://127.0.0.1:8000`). This repo does not change Tailscale ACLs,
Aperture grants, the key value, or firewall rules. ACLs stay in
`javdl/joost`.

### Units

`users/dsv41-mia.nix` installs `dsv41-mia.service` on spark only, wanted
by `default.target`. spark2 has no model unit. `start.sh` on the head
sshes to `joost@192.168.100.11` and starts rank 1 there, then starts rank
0 locally. That is the whole pair. There is no worker unit to lose the
boot race with the head (`Start request repeated too quickly` on the
sybil worker).

The unit runs the checkout at `~/mia29/recipe`:

```bash
FOREGROUND=1 PREPARE=0 SERVED_NAME=dsv41 PORT=8000 HOST=127.0.0.1 \
  TENSORFOLD_NO_UPDATE_CHECK=1 bash ./start.sh
```

`PATH` starts with `~/mia29/shimw`, then `~/glm-dl/venv/bin` and the
system directories. `PREPARE=0` means a restart does not download weights
or build the image. Both machines already have
`tensorfold-dsv41:exl3-tp2-625d420e24a4`. The checkout must be exactly
`370daf0cc38f348516a98ebab38f6053858eab1f` (Mia's recipe commit that added
the systemd template). `start.sh`, `stop.sh`, and
`scripts/{config,nodes,prepare}.sh` must be clean against that commit.
`scripts/local.sh` is not in git. It has to mention `/mnt/models/mia29`.
The unit passes the serving settings in its environment, and the recipe
lets the environment win over `local.sh`: `CONTEXT=262144`,
`PARALLEL=4`, `DRAFTS=1`, `API_KEY=1`, `THINKING=1`,
`WORKER=joost@192.168.100.11`, and the image name above.

Before `start.sh`, the unit waits (and then fails the start, which counts
toward the limit below) until all of these are true:

- `192.168.100.10/24` is on `enp1s0f0np0` (up to 120s)
- `ssh -o BatchMode=yes joost@192.168.100.11 true` works (up to 180s)
- `/mnt/models/mia29` is a directory on an nfs mount (up to 120s). A stat
  trips the automount. `findmnt -T` prints one fstype per line: `autofs`,
  then `nfs4` once the export is stacked on it. nfs on any line counts.
  `autofs` alone keeps waiting, then the start fails
- the same image is present on spark2, and `/mnt/models/mia29` is a
  directory there
- nothing is listening on port 8000, and the transient unit `mia29-tf` is
  not active
- `spark-vllm.service` and `nvpair.service` are inactive, as a system unit
  and as a user unit

`start.sh` exits 0 when both ranks are already running, and
`Restart=on-failure` does not restart a success. The port check is what
stops a switch from "adopting" a hand-started server and then going
inactive. Stop the hand-started server first. The stop script is
`~/mia29/recipe/stop.sh`. It stops both ranks.

`Type=simple`. The unit is active as soon as `start.sh` is forked, which
is before the weights are loaded. `TimeoutStartSec` is 15 minutes and
covers the waits above, not the load. `TimeoutStopSec` is 120 seconds.
Stop sends SIGTERM, `start.sh` runs `stop.sh` from that trap, and
`ExecStopPost` runs `stop.sh` again. The second run finds nothing and
exits 0.

`Restart=on-failure`, `RestartSec=60`, `StartLimitIntervalSec=30min`,
`StartLimitBurst=3` (the first start counts). After three failed starts
in half an hour the unit stays failed. That cap is the one already used
on the live transient unit. spark's GPU faulted more than once on 26 Oct
2026 during a UPS incident, so nothing else restarts it. The health timer
does not.

`dsv41-mia-health.timer` is once a minute, log only. It is wanted by
`timers.target` and has no `After=` of its own. Putting `After=` on a
timer that `timers.target` pulls in, while the service orders after
`basic.target`, made systemd drop the `timers.target` job on the sybil
health timer. The oneshot the timer starts is ordered `After=dsv41-mia.service`.
For the first 15 minutes the unit is active, a failed `/health` is
ignored, because that is the load. After that, a failure is one journal
line (`Not restarting.`) and exit 0. `GET /health` does not send the key.

`Conflicts=spark-vllm.service` and `Conflicts=nvpair.service` are the same
idea as the old head. A user unit cannot stop a system unit. The preflight
refuses to start while either is active in either manager. This module
does not enable, disable, or restart `spark-vllm`, `nvpair`, Docker, the
driver, or the DGX dashboard. Leave those two disabled.

### Key

Mia reads one raw line from `~/.local/state/dsv41-tensorfold/api-key`
(mode `600`, not a symlink). The engine rereads that file when it
changes. The unit's `ExecStartPre` writes it from `VLLM_API_KEY` in
`~/.config/spark-vllm/api.env` (mode `600`, not a symlink). One
surrounding pair of single or double quotes in `api.env` is file syntax
and is not part of the key. The value is not printed and is not in the
Nix store. Replacing `api.env` does not update the raw file until the
next start of `dsv41-mia`.

`/v1/*` needs `Authorization: Bearer` with that line. `/health` does not.

### Known limits

Thinking is on unless the request turns it off. The recipe's own smoke
test sends `chat_template_kwargs.enable_thinking: false`. This TensorFold
build returns HTTP 400 for `response_format` and other guided-decoding
fields. Ask for a shape in the prompt. Clients keep using the model name
`dsv41`.

### Start and stop

Linger has to be on, or a reboot does not start the user unit. See the
first-switch section above.

```bash
systemctl --user start dsv41-mia.service
systemctl --user status dsv41-mia.service
journalctl --user -u dsv41-mia -f
curl -sf http://127.0.0.1:8000/health
systemctl --user stop dsv41-mia.service
```

Stop from systemd, not `./stop.sh`, while the unit is active. A container
that disappears out from under `start.sh` is a failure, and the unit
restarts within the limit above. `systemctl --user reset-failed dsv41-mia`
clears the start limit.

`https://spark.buri-hoki.ts.net:8443/health` is the same server through
Tailscale Serve. LAN, CX7, and tailnet clients of port 8000 itself still
do not connect. The bind is localhost.

A `home-manager switch` on spark starts `dsv41-mia` when it is not
already active. It does not start `dsv41-cluster-head` or
`dsv41-cluster-health.timer`. A switch on spark2 does not start
`dsv41-cluster-worker`, `dsv41-cluster-follow.service`, or
`dsv41-cluster-follow.timer`. Those four exist in
`users/dsv41-cluster.nix` and are installed only when
`services.dsv41Cluster.enable` is true. The profile sets that to false.

Changing the Mia unit file and switching restarts the service. That is one
cold load, a few minutes when the rank caches are warm, not a second model.

### Roll back to sybil EXL3

Stop Mia, then flip both options in `users/joost/home-manager-spark.nix`
and switch spark2 before spark. The assertion in `users/dsv41-mia.nix`
refuses a config that enables both.

```nix
services.dsv41Mia.enable = false;
services.dsv41Cluster.enable = true;
```

```bash
systemctl --user stop dsv41-mia.service
make switch NIXNAME=spark2
make switch NIXNAME=spark
```

Stopping Mia runs `stop.sh` on both ranks. The spark2 switch installs
`dsv41-cluster-worker` and `dsv41-cluster-follow.timer`. The spark switch
installs `dsv41-cluster-head`, `dsv41-cluster-ready`, and
`dsv41-cluster-health.timer`. `dsv41-cluster-serve` stays. What those
units do, and the image and weights they require, is the next section.
The sybil cold load was about 6.5 minutes.

To turn the model off entirely, set `services.dsv41Mia.enable = false` and
leave the sybil option false. Serve keeps publishing `:8443` at whatever
is on `127.0.0.1:8000`.

## Sybil EXL3 cluster

Not installed unless `services.dsv41Cluster.enable` is true. The profile
sets it false. The definition is `users/dsv41-cluster.nix`.
Changing the image digest, weights path, DSpark table, served name, port,
API key path, or the CX7 rendezvous is a one-line edit in that file and
applies to both machines. Each home imports it and, when the option is
on, runs the unit for its own node:

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
  (mode `600`, not a symlink). Either `VLLM_API_KEY=secret` or
  `VLLM_API_KEY="secret"` (one surrounding pair of single or double
  quotes) is accepted. The file handed to `docker --env-file` is
  written unquoted: Docker 29 keeps quote characters as part of the
  value, vLLM then treats them as the key, and every request returns
  401. The value is passed as `vllm serve --api-key`. It is not in the
  repo or the Nix store.

`expose = "open"` in the cluster attrset is the previous listener:
`0.0.0.0:8000`, no key, and this module does not publish Tailscale Serve.
Set that in `users/dsv41-cluster.nix`, not in only one host. Switching to
`open` does not clear an existing Serve config.

The head unit becomes active when the container process is running.
`TimeoutStartSec` on spark is 4 minutes and covers `ExecStartPre` (fabric
address, image check, API key file). Model load is `dsv41-cluster-ready`,
a oneshot the head starts with `systemctl --user start --no-block`. It is
not installed into a target, so `home-manager switch` does not wait for
it. The oneshot polls `GET /health` on `127.0.0.1:8000` (no key) for about
20 minutes (80 tries, 15 seconds apart). A cold load is about 6.5 minutes
plus pairing. When `/health` answers, it makes one authenticated
`GET /v1/models`. Success is a line in that unit's journal. A 401 is a
key mismatch: fix `api.env`, then
`systemctl --user restart dsv41-cluster-head`. If `/health` never answers,
the oneshot restarts the head.

`dsv41-cluster-health.timer` (every 15 seconds, `AccuracySec=1s`) is the
watchdog. It does not probe until `dsv41-cluster-ready` has succeeded and
that success is at least 60 seconds old, so the cold load (~6.5 minutes)
and the first minute of serving are not strikes.

After that, each tick looks at the worker's TCPStore connection first.
The head listens dual-stack, so spark2's connection to
`192.168.100.10:25000` is an IPv4-mapped socket in `/proc/net/tcp6`
(`0000000000000000FFFF0000` plus the little-endian IPv4), not a row in
`/proc/net/tcp`. Both tables are read. The identity is the source port of
an established socket whose remote address is spark2's CX7 address. An
extra socket on the same port does not count: the previous port has to be
gone. Two consecutive ticks with a new port, or with the connection gone,
restart `dsv41-cluster-head` without waiting on a chat call. That is the
fast path for a spark2 worker restart, about 15-30 seconds. Before tcp6
was parsed, that path never armed. On the hardware the same restart was
detected only by the chat probe, in 2 minutes 5 seconds, and the cluster
was back 8 minutes 28 seconds after the worker restart. The rest of that
interval is the cold load.

Otherwise the tick checks `GET /health` (no key, 10 seconds) and then one
authenticated 1-token `POST /v1/chat/completions` to `127.0.0.1:8000`
(`max_tokens` 1, 20 second curl timeout). In the Aperture profile the chat
probe sends the key. The timer interval is shorter than that timeout, so
a hung probe is followed immediately by the next one. A chat timeout also
scrapes `GET /metrics` with the same key. If `num_requests_running` is
above zero and `prompt_tokens_total` or `generation_tokens_total` has
increased since the previous scrape, the engine is in a prefill and the
timeout is not a strike. The first busy scrape only records the baseline.
A measured 120K-token prompt took 65.9 seconds to first token and caused
three probe timeouts. A 252K-token prompt took 146.6 seconds, long enough
to reach five strikes. `max_model_len` is 262144, so a prefill of that
length can happen in production. Those timeouts do not restart the head
while the counters move. Chunked prefill is 2048 tokens, about a second
at the measured rate, so a 20 second gap should see the prompt counter
advance. If a build only increments those counters when the request
finishes, a max-context prefill still looks frozen.

Five chat failures while the counters are frozen, or while no request is
running, or while `/metrics` cannot be scraped, are about 100 seconds of
probes. The frozen case spends one extra probe recording the baseline, so
the worst case is about 120 seconds plus up to 15 seconds if the hang
starts just after a successful probe, under 2.5 minutes. A 401 from the
chat probe is logged and does not by itself restart the head. The key is
read from `~/.config/spark-vllm/api.env` and is not logged.

Stopping the head runs `docker stop` and then `ExecStopPost` (`docker rm
-f`). A killed `docker run --rm` client can leave `dsv41-serve` behind;
the remove is what clears it. The same stop path is on the worker.

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

This switch is the sybil cluster, and only after
`services.dsv41Cluster.enable = true` and `services.dsv41Mia.enable = false`
in `users/joost/home-manager-spark.nix`. A switch with the profile as it is
does not install these units. See [Roll back to sybil EXL3](#roll-back-to-sybil-exl3).

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
# one line, mode stays 600. Quotes around the value are optional:
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

`make switch` on spark returns once `dsv41-serve` is launched. It does
not wait for the weights to load. Follow readiness with
`journalctl --user -u dsv41-cluster-ready -f`. Then check
`https://spark.buri-hoki.ts.net:8443/health`.

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

### Stop sybil and clear Tailscale Serve

With the profile defaults, sybil is already out of the generation. These
commands are for a host that still has `services.dsv41Cluster.enable = true`.
The off command removes the `:8443` publication; it does not restore the
previous mapping to `:8888`. Mia's rollback does not clear Serve.

```bash
# spark: stop the readiness poll first so it cannot restart the head
systemctl --user stop dsv41-cluster-ready.service
systemctl --user disable --now dsv41-cluster-head dsv41-cluster-serve dsv41-cluster-health.timer
tailscale serve --https=8443 off
# spark2
systemctl --user disable --now dsv41-cluster-worker dsv41-cluster-follow.timer
```

`disable --now` removes the Home Manager symlinks under
`~/.config/systemd/user/` (`default.target.wants/` and `timers.target.wants/`)
until the next switch. The unit files stay in that generation. The next
switch starts sybil again only if `services.dsv41Cluster.enable` is still
true. Leaving it false, which is the profile default, keeps the head,
worker, health timer, and follow timer out. To serve on every interface
again, set `expose = "open"` in `users/dsv41-cluster.nix` and switch both
hosts. That also drops `dsv41-cluster-serve`. Re-run `dsv41_tp2.sh up`
only after the cluster units are stopped, or the two will fight over the
container name `dsv41-serve`. Stopping the head also runs `docker rm -f
dsv41-serve`, so a container that outlived the unit is removed.

## Do not manage or restart

- `spark-vllm` on spark (Docker vLLM serving Hermes on `:8888`, container
  `spark-qwen36-nvfp4`). It is not a service in this flake. `dsv41-mia`
  (and the sybil head, when that option is on) refuses to start while
  `spark-vllm.service` or `nvpair.service` is active. Leave both
  disabled. This module does not stop them.
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
