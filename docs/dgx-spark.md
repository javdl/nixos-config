# DGX Spark (`spark`, `spark2`)

Two NVIDIA DGX Sparks. They are standalone Home Manager outputs, the same
kind as the Omarchy boxes: `mkOmarchyHome` in `flake.nix` with
`isDgxSpark = true`, `system = "aarch64-linux"`, and `hostName` `spark` or
`spark2`. `homeConfigurations."spark"` and `."spark2"` sit next to fu137,
j9, and mba.

`isDgxSpark` is the headless flag. It turns off the Quattro assumptions
that do not fit DGX OS: the Omarchy startup module (Hyprland autostart,
walker, mako), the hypr/omarchy file guards, the pacman package filter,
tailmix, pinentry's `/usr/bin/pinentry` symlink, and the desktop package
blocks. Shell and git modules stay on, because nothing else owns those
files. The agent CLI module (`users/agent-clis.nix`) is the one
`mkOmarchyHome` already imports. `herdr` comes from the overlay in
`lib/overlays.nix`.

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
Do not install tailmix here: each Spark is on `buri-hoki` only.

Nix may not be installed yet. Use the same Determinate installer as Omarchy,
then `make test` / `make switch`. The Makefile takes the non-NixOS branch on
Ubuntu and runs Home Manager.

## What Home Manager manages

User `joost` (`/home/joost`).

- The shared headless profile: agent CLIs, `herdr`, git, bash, tmux,
  neovim, starship, zoxide, delta. Extra packages on top: `mosh`, `tmux`,
  `iperf3`, `bubblewrap` (Codex sandbox). GUI apps, fonts, NVIDIA Sync,
  Nsight, browsers, and a Nix `docker` that would shadow DGX OS Docker are
  left out.
- `herdr-agents` user service from `users/herdr-fleet.nix` (node mode).
  `ExecStart` is the store path of the overlay `herdr`. Fleet `remoteBin`
  is `/home/joost/.nix-profile/bin/herdr`, same shape as fu137. The
  activation appends the controller public keys in
  `users/herdr-fleet-keys.nix` to `~/.ssh/authorized_keys` when the full
  line is absent. It does not remove existing lines.
- Rendered files under `~/.config/dgx-spark/` (see below). A switch does
  not copy them into `/etc`.

`scripts/bootstrap-herdr-node.sh` exits immediately on these hostnames.
The 0.9.3 binary it installs to `~/.local/bin` is the exe.dev pin. The
overlay is newer. Re-running the script would put the old unit back.

### chezmoi owns `~/.ssh/config`

`chezmoiSync` in `users/joost/home-manager.nix` bootstraps javdl/dotfiles
and applies `~/.ssh/config`. Home Manager does not write the CX7 aliases.
The first switch can replace a hand-edited `~/.ssh/config` and drop them
until the Host blocks below land in javdl/dotfiles. That repo is the
follow-up. Do not add a second writer here.

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

`-b backup` backs up files Home Manager replaces. Expect it to:

- start `moshi-hook` (user service from `users/agent-clis.nix`)
- replace `~/.config/systemd/user/herdr-agents.service` and restart the
  `agents` session
- append bali and cmdpane keys to `authorized_keys` if the exact line is
  missing
- run the same non-lite activations as an Omarchy profile (Claude installer
  if `~/.local/bin/claude` is missing, cargo installs for worktrunk and
  caut, chezmoi)

`agent-mail` has no aarch64-linux build in the overlay, so that user
service is absent. Linger has to be on or the user service stops at
logout:

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

## Do not manage or restart

- `spark-vllm` on spark (Docker vLLM serving Hermes on `:8888`, container
  `spark-qwen36-nvfp4`). A later opt-in could wrap it. It is not a service
  in this flake.
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
