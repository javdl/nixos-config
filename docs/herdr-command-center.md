# Herdr fleet: Bali command center

`bali` is the persistent Herdr command center. It runs the named `agents`
session and uses `herdr-mirror` to present workspaces from three regular
runners, the fu137 GPU workstation, a maximum-size exe.dev development VM,
radon (Mac Studio) and the two DGX Sparks in one sidebar.

```text
operator
   |
   | ssh bali
   v
bali: Herdr session "agents" + herdr-mirror
   |-- r03 --> github-runner-03 (regular)
   |-- r04 --> github-runner-04 (regular)
   |-- r05 --> github-runner-05 (regular)
   |-- fu137 --> fu137          (GPU, watch-first)
   |-- exe --> fu-herdr-dev     (exe.dev, 4 vCPU / 16 GB)
   |-- rad --> radon            (macOS, personal tailnet)
   |-- sp1 --> spark            (DGX Spark, personal tailnet)
   `-- sp2 --> spark2           (DGX Spark, personal tailnet)
```

Herdr remains host-local on every machine. Mirror streams the remote terminal
and agent state over SSH; it does not move processes to Bali. Closing the
operator's SSH client therefore leaves every server-owned pane running.

## Inventory

| Fleet name | Machine | Role | SSH target | Sidebar prefix | Mirror mode |
|---|---|---|---|---|---|
| `runner03` | `github-runner-03` | regular | `100.126.150.43` | `r03` | control |
| `runner04` | `github-runner-04` | regular | `100.97.77.46` | `r04` | control |
| `runner05` | `github-runner-05` | regular | `100.108.96.124` | `r05` | control |
| `fu137` | fu137 Omarchy boot | GPU | `fu137` SSH alias, port 2222 | `fu137` | watch-first |
| `exedev` | `fu-herdr-dev` | dev | `fu-herdr-dev` SSH alias | `exe` | control |
| `radon` | radon (nix-darwin) | mac | `radon` SSH alias, port 2222 | `rad` | control |
| `spark` | DGX Spark (Ubuntu) | gpu | `spark` SSH alias, port 2222 | `sp1` | control |
| `spark2` | DGX Spark (Ubuntu) | gpu | `spark2` SSH alias, port 2222 | `sp2` | control |

Bali runs Tailscale with DNS acceptance disabled. The runner inventory uses
stable tailnet IPs, while Bali's chezmoi-owned SSH config maps `fu137` to
`100.92.74.63` and selects the fleet key. The exe.dev worker uses the dotless
`fu-herdr-dev` SSH alias, which selects Bali's FashionUnited team key without
matching its personal `*.exe.xyz` block. If a tailnet machine is re-enrolled
and its IP changes, update the matching inventory or SSH-config entry.

radon and the Sparks are in the personal tailnet and reach Bali through
declarative node sharing (`fuww/fashionunited` and `javdl/joost`,
`infra/tailscale/policy.hujson`). Their Tailscale SSH cannot admit Bali:
the `ssh` policy section rejects cross-tailnet sources. Bali's chezmoi SSH
config therefore maps their aliases to the tailnet IP and OpenSSH on port
2222, which accepts Bali's `id_ed25519_nopass` key. On radon that sshd is the
`sshd-bali` launchd daemon in `hosts/radon.nix`; the Herdr server there is a
Home Manager LaunchAgent (login keychain access for Claude Code), so radon
needs a logged-in user session.

The fu137 mirror sets `always_control = false`: it observes without changing the
visible fu137 terminal geometry until somebody types into the mirrored pane.
The headless runners and exe.dev worker stay writable and follow the controller
pane size.

The three runners and fu137 accept Bali over OpenSSH carried by Tailscale.
fu137 remains a user-owned Arch/Omarchy workstation; because Bali is tagged
`tag:devboxes`, Tailscale SSH cannot connect from Bali to fu137. Regular
OpenSSH on port 2222 (fu137 keeps Tailscale SSH on 22 for its owner) preserves
fu137's user identity while the tailnet policy and its interface-scoped
firewall rule keep 2222 private. fu137 is a worker only:
the mirror package, `hosts.toml`, and plugin activation are all gated on
`controller`, which fu137 does not set.

## Declarative pieces

- `users/herdr-fleet.nix` is the fleet source of truth. It generates the node
  service, both controllers' configs, `hosts.toml`, and the `herdctl` helper.
  Each node carries one SSH destination per controller (`fromBali`,
  `fromCmdpane`).
- `users/herdr-fleet-keys.nix` holds the controllers' public keys; fu137, the
  runners (2222) and radon (2222) authorize them from there.
- `modules/herdr-fleet-node.nix` adds a minimal `joost` Home Manager profile to
  a NixOS node while leaving the `github-runner` CI account isolated.
- `users/herdr-mirror-plugin.toml` is the local plugin manifest. The upstream
  network build step is removed because Nix supplies the verified binary.
- `scripts/bootstrap-herdr-node.sh` installs the checksum-pinned Herdr
  binary (x86_64 or aarch64), integrations, config, and lingering user service
  on a non-Nix Ubuntu node (exe.dev worker, Sparks).
- `hosts/github-runner-{03,04,05}.nix` import the node module.
- `users/joost/home-manager-server.nix` enables controller mode only on Bali.
- `users/joost/home-manager.nix` enables node mode on fu137 and radon without touching
  Omarchy-owned desktop, terminal, Hyprland, or package configuration.

The repo pins Herdr `0.9.3` in `lib/overlays.nix` (and the same release in
the bootstrap script) and herdr-mirror `0.4.1` in
`users/herdr-fleet.nix`. The mirror release checksum is verified by Nix. Stable
Herdr 0.8.2 exposes the terminal session streams the mirror uses.

All machines use the named `agents` session. A lingering systemd user service
starts `herdr --session agents server`, so the server is owned by the user
manager rather than an SSH connection or `tailscaled.service` cgroup.

## exe.dev worker

`fu-herdr-dev` is a copy of `fu-dev-golden`, not `fu-preview-golden`. The dev
image contains the monorepo, its synced repositories, and mise toolchains; the
preview image contains only the static-site serving stack. The live Team plan
allows at most 4 vCPU and 16 GB RAM per VM, so the worker uses both maxima. Its
40 GB disk is the source size and cannot be reduced during a copy.

The source must be flushed before copying because exe.dev snapshots can omit
very recent unflushed writes:

```bash
ssh exe-work ssh fu-dev-golden sync
ssh exe-work cp fu-dev-golden fu-herdr-dev \
  --copy-tags --cpu=4 --memory=16GB --disk=40GB --json
ssh exe-work tag fu-herdr-dev herdr agent-worker --json
ssh exe-work comment fu-herdr-dev \
  'Herdr dev worker; cloned from fu-dev-golden; controlled by Bali' --json
```

Both fu137 and Bali use a dotless `Host fu-herdr-dev` alias to select the
FashionUnited team exe.dev key. Bali additionally sets `HostKeyAlias exe.dev`,
reusing the platform key already pinned to the fingerprint documented by
exe.dev. Bootstrap or refresh the worker by streaming the reviewed script:

```bash
ssh fu-herdr-dev 'bash -s' < scripts/bootstrap-herdr-node.sh
ssh spark 'bash -s' < scripts/bootstrap-herdr-node.sh
ssh spark2 'bash -s' < scripts/bootstrap-herdr-node.sh
```

The bootstrap is idempotent, installs the pinned Herdr release, enables linger
(via sudo, only when it is not already on), and verifies a representative
workspace command after starting the `agents` service.

## exe.dev command pane

A second controller on an exe.dev VM in the personal exe.dev account
(j@jlnw.nl), Home Manager output `homeConfigurations.herdr-cmdpane` (user
`exedev`). It mirrors every node except the team-account exe.dev worker (that
needs the FashionUnited team key) and except Bali itself (Bali's session
already holds mirrored workspaces; mirroring a mirror would duplicate them).

The VM joins the personal tailnet through exe.dev's Tailscale workload
identity federation, so no auth key sits on it, and gets `tag:cmdpane`. A
tagged node cannot use Tailscale SSH into user-owned devices, and the
work-tailnet nodes are cross-tailnet, so every destination is OpenSSH:

| Node | Destination | Policy |
|---|---|---|
| runner03–05 | tailnet IP, port 2222 (`modules/herdr-fleet-node.nix`) | fuww: `tag://personal/cmdpane` → `tag:github-runner` tcp:2222 |
| fu137 | `100.92.74.63`, port 2222 (`sshd_config.d` drop-in) | fuww: `tag://personal/cmdpane` → `herdr-fu137` tcp:2222 |
| radon | `100.92.105.21`, port 2222 (`sshd-bali`) | javdl/joost: `tag:cmdpane` → own devices, `tag:hermes` tcp:2222 |
| spark, spark2 | tailnet IP, port 2222 | same grant |

Its key is `~/.ssh/herdr-cmdpane` (public half in
`users/herdr-fleet-keys.nix`). The Sparks are not Nix-managed: their
`~/.ssh/authorized_keys` carries the key by hand.

Set it up once:

1. Create the VM in the personal account (`ssh exe new --name herdr-cmdpane`).
2. In the personal tailnet's admin console, add a trust credential (OpenID
   Connect, custom issuer) with the Issuer and Subject from an exe.dev
   **Identity Federation → Tailscale** integration named `tailscale-wif`
   attached to the VM. Scope: Auth Keys write; tag: `tag:cmdpane`. Paste the
   Client ID back into the integration.
3. From a workstation (it reaches both Bali and the personal exe.dev
   account), move the private key from Bali, where it was generated, to the
   VM, delete Bali's copy, and run the bootstrap:

   ```bash
   ssh bali 'cat ~/.ssh/herdr-cmdpane' \
     | ssh herdr-cmdpane.exe.xyz 'umask 077; mkdir -p ~/.ssh; cat > ~/.ssh/herdr-cmdpane'
   ssh bali 'rm ~/.ssh/herdr-cmdpane ~/.ssh/herdr-cmdpane.pub'
   ssh herdr-cmdpane.exe.xyz 'bash -s' < scripts/bootstrap-herdr-cmdpane.sh
   ```

The bootstrap installs Tailscale and joins (not ephemeral, so a paused VM
keeps its node), installs Nix, enables linger, applies the Home Manager
output, and runs `herdctl <node> workspace list` against every node. Attach
with `ssh herdr-cmdpane.exe.xyz` and `herdr session attach agents`.

## First rollout

From fu137, build the NixOS closures directly and use the configured Home
Manager test target for fu137 itself:

```bash
nix build --no-link \
  '.#nixosConfigurations.bali.config.system.build.toplevel' \
  '.#nixosConfigurations.github-runner-03.config.system.build.toplevel' \
  '.#nixosConfigurations.github-runner-04.config.system.build.toplevel' \
  '.#nixosConfigurations.github-runner-05.config.system.build.toplevel'
make test NIXNAME=fu137
```

After the change is on `main`, the NixOS machines pick it up during their 04:00
auto-update. For an immediate rollout:

```bash
ssh bali 'sudo nixos-rebuild switch --flake "github:javdl/nixos-config#bali"'
ssh joost@100.126.150.43 'sudo nixos-rebuild switch --flake "github:javdl/nixos-config#github-runner-03"'
ssh joost@100.97.77.46 'sudo nixos-rebuild switch --flake "github:javdl/nixos-config#github-runner-04"'
ssh joost@100.108.96.124 'sudo nixos-rebuild switch --flake "github:javdl/nixos-config#github-runner-05"'
```

Apply the standalone Home Manager output on fu137:

```bash
make switch NIXNAME=fu137
```

That activation starts the `agents` Herdr user service and idempotently appends
the controllers' public keys to the existing user-owned `authorized_keys`
file. It does not replace the file or remove other trusted keys.

fu137 keeps Tailscale SSH on port 22 for Joost's own devices. The
controllers (Bali, tagged; the command pane, cross-tailnet) cannot use it, so
OpenSSH also listens on 2222, reachable only over `tailscale0`:

```bash
printf 'Port 22\nPort 2222\n' | sudo tee /etc/ssh/sshd_config.d/50-herdr-2222.conf
sudo sshd -t && sudo systemctl enable --now sshd && sudo systemctl restart sshd
sudo ufw allow in on tailscale0 to any port 2222 proto tcp \
  comment 'Herdr controllers'
sudo loginctl enable-linger joost
loginctl show-user joost -p Linger
```

The work tailnet policy grants Bali (`herdr-bali`) and the command pane
(`tag://personal/cmdpane`) TCP 2222 on fu137 (`herdr-fu137`). Do not add a
Tailscale `ssh` rule for this path: that section controls Tailscale SSH, whose
tagged-to-user-owned restriction is why OpenSSH is used. Do not add a global
firewall rule either; the `tailscale0` rule leaves the public interface under
UFW's default-deny policy.

`loginctl enable-linger` is what keeps `herdr-agents` running across logout and
reboot, independently of SSH sessions.

Authorize the connection once from Bali:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 fu137 \
  'HERDR_SESSION=agents herdr status server --json'
```

No `/usr/share/omarchy` files are modified.

## Agent authentication

Herdr and its Codex/Claude integrations are installed on the regular nodes,
but provider login is deliberately not copied between machines. Complete each
interactive login as `joost`:

```bash
ssh joost@100.126.150.43
codex login
claude
herdr integration status
```

Repeat for runners 04 and 05. fu137 already has current Claude and Codex Herdr
integrations. The exe.dev golden image supplies the agent binaries but no
credentials, so complete the same interactive logins through
`ssh fu-herdr-dev`. Bali's existing agent configuration remains
user/chezmoi-owned. Do not copy API keys, OAuth files, or subscription
credentials into this repo.

## Verification

On every machine:

```bash
systemctl --user status herdr-agents
HERDR_SESSION=agents herdr status server --json
herdr integration status
```

From Bali, SSH must be non-interactive and every remote server must answer:

```bash
for ip in 100.126.150.43 100.97.77.46 100.108.96.124; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 "joost@$ip" \
    'HERDR_SESSION=agents herdr status server --json'
done
ssh -o BatchMode=yes -o ConnectTimeout=5 fu137 \
  'HERDR_SESSION=agents herdr status server --json'
ssh -o BatchMode=yes -o ConnectTimeout=8 exedev@fu-herdr-dev \
  'HERDR_SESSION=agents ~/.local/bin/herdr status server --json'
```

Then check the controller:

```bash
herdr plugin list --json
herdr-mirror status
herdctl hosts
herdctl runner03 status server --json
```

The expected plugin is `mirror`, version `0.4.1`, enabled. The expected safety
setting in `~/.config/herdr-mirror/hosts.toml` is:

```toml
close_remote_on_local_close = false
```

## Daily use

Start at Bali:

```bash
ssh bali
herdr
```

New login shells receive `HERDR_SESSION=agents`. In an old shell, use
`HERDR_SESSION=agents herdr`. Mirror autostarts after a workspace receives
focus.

Controller bindings use Herdr's normal `ctrl+b` prefix unless changed later:

| Binding | Action |
|---|---|
| `prefix` then `Shift+M` | start or resume mirror |
| `prefix` then `Shift+S` | pause mirror |
| `prefix` then `Shift+B` | restore locally closed mirrors |
| `prefix` then `Shift+N` | choose a host for a new workspace |

Useful non-interactive commands:

```bash
herdctl hosts
herdctl fu137 workspace list
herdctl exedev workspace list
herdctl runner04 agent list
herdctl runner05 agent read reviewer --source recent-unwrapped --lines 120
```

`herdctl` shell-quotes all remote arguments and forces the shared `agents`
session. Use raw SSH for non-Herdr administration.

## Add a node later

1. Give the machine a stable SSH target and verify Bali can use non-interactive
   SSH. Tailnet nodes use their stable IP; exe.dev team VMs use a dotless alias
   so the correct account identity wins.
2. Import `modules/herdr-fleet-node.nix` from the NixOS host. For a non-NixOS
   host, import `users/herdr-fleet.nix` from its Home Manager profile with
   `provisionAgentRuntime = true`.
3. Add one entry to `fleetNodes` in `users/herdr-fleet.nix`, including its role,
   SSH user and target, sidebar prefix, Herdr path, and control policy.
4. Evaluate and deploy both the node and Bali. Bali's generated `hosts.toml` and
   `herdctl` inventory update from the same entry.
5. Authenticate the agent CLIs locally and run the verification block above.

Upstream references: [Herdr persistence and remote access](https://herdr.dev/docs/persistence-remote/),
[Herdr integrations](https://herdr.dev/docs/integrations/), and
[herdr-mirror](https://github.com/nikok6/herdr-mirror).
