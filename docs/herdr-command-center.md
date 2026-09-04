# Herdr fleet: Bali command center

`bali` is the persistent Herdr command center. It runs the named `agents`
session and uses `herdr-mirror` to present workspaces from three regular
runners, the fu137 and j9 GPU workstations, the j8 Mac Studio, and a
maximum-size exe.dev development VM in one sidebar.

```text
operator
   |
   | ssh bali
   v
bali: Herdr session "agents" + herdr-mirror
   |-- r03 --> github-runner-03 (regular)
   |-- r04 --> github-runner-04 (regular)
   |-- r05 --> github-runner-05 (regular)
   |-- gpu --> fu137            (GPU, watch-first)
   |-- j9  --> j9               (GPU, watch-first)
   |-- j8  --> j8               (macOS, watch-first)
   `-- exe --> fu-herdr-dev     (exe.dev, 4 vCPU / 16 GB)
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
| `gpu` | fu137 Omarchy boot | GPU | `fu137` SSH alias | `gpu` | watch-first |
| `j9` | j9 Omarchy boot | GPU | `100.115.211.110` | `j9` | watch-first |
| `j8` | j8 Mac Studio (Darwin) | mac | `100.67.159.69` | `j8` | watch-first |
| `exedev` | `fu-herdr-dev` | dev | `fu-herdr-dev` SSH alias | `exe` | control |

Bali runs Tailscale with DNS acceptance disabled. The runner, j9 and j8
inventory entries use stable tailnet IPs, while Bali's chezmoi-owned SSH config
maps `fu137` to `100.92.74.63` and selects the fleet key. The exe.dev worker
uses the dotless `fu-herdr-dev` SSH alias, which selects Bali's FashionUnited
team key without matching its personal `*.exe.xyz` block. If a tailnet machine
is re-enrolled and its IP changes, update the matching inventory or SSH-config
entry. Note that j8 and j9 are also reachable on the personal tailnet under
different addresses; the inventory deliberately uses the addresses they hold on
Bali's own tailnet (`j9` = `100.115.211.110`, `j8-1` = `100.67.159.69`).

The three workstation mirrors set `always_control = false`: they observe
without changing the visible fu137/j9/j8 terminal geometry until somebody types
into the mirrored pane. The headless runners and exe.dev worker stay writable
and follow the controller pane size.

The three runners and the three workstations accept Bali over OpenSSH carried
by Tailscale. fu137 and j9 remain user-owned Arch/Omarchy machines and j8 a
user-owned Mac; because Bali is tagged `tag:devboxes`, Tailscale SSH cannot
connect from Bali to any of them. Regular OpenSSH preserves their user identity
while the tailnet policy and an interface-scoped firewall rule keep port 22
private. They are workers only: the mirror package, `hosts.toml`, and plugin
activation are all gated on `controller`, which none of them set.

j8 is the one Darwin node. Home Manager has no systemd there, so
`users/herdr-fleet.nix` starts the same `agents` session from a launchd agent
(`~/Library/LaunchAgents/org.nix-community.home.herdr-agents.plist`, logging to
`/tmp/herdr-agents.log`) instead of a `systemd --user` unit, and its
`remote_bin` is the nix-darwin per-user profile path
`/etc/profiles/per-user/joost/bin/herdr`.

## Declarative pieces

- `users/herdr-fleet.nix` is the fleet source of truth. It generates the node
  service, Bali's controller config, `hosts.toml`, and the `herdctl` helper.
- `modules/herdr-fleet-node.nix` adds a minimal `joost` Home Manager profile to
  a NixOS node while leaving the `github-runner` CI account isolated.
- `users/herdr-mirror-plugin.toml` is the local plugin manifest. The upstream
  network build step is removed because Nix supplies the verified binary.
- `scripts/bootstrap-herdr-exe-node.sh` installs the checksum-pinned Herdr
  binary, integrations, config, and lingering user service on an Ubuntu node.
- `hosts/github-runner-{03,04,05}.nix` import the node module.
- `users/joost/home-manager-server.nix` enables controller mode only on Bali.
- `users/joost/home-manager.nix` enables node mode on fu137, j9 and j8 (it
  imports `users/herdr-fleet.nix`, which matches `currentSystemName` against its
  `workstationWorkers` list) without touching Omarchy-owned desktop, terminal,
  Hyprland, or package configuration.

The repo pins Herdr `0.8.2` in `lib/overlays.nix` and herdr-mirror `0.4.1` in
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
ssh fu-herdr-dev 'bash -s' < scripts/bootstrap-herdr-exe-node.sh
```

The bootstrap is idempotent, installs Herdr 0.8.2 from its checksum-pinned
release binary, enables linger for `exedev`, and verifies a representative
workspace command after starting the `agents` service.

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

Apply the standalone Home Manager output on each Omarchy workstation, from the
machine itself:

```bash
make switch NIXNAME=fu137
make switch NIXNAME=j9
```

That activation starts the `agents` Herdr user service and idempotently appends
Bali's fleet public key to the existing user-owned `authorized_keys` file. It
does not replace the file or remove other trusted keys.

```bash
sudo tailscale set --ssh=false
sudo ufw allow in on tailscale0 to any port 22 proto tcp \
  comment 'Herdr command center'
sudo systemctl enable --now sshd
sudo loginctl enable-linger joost
loginctl show-user joost -p Linger
```

The tailnet policy must grant Bali (`100.113.194.113`) access to fu137
(`100.92.74.63`) and j9 (`100.115.211.110`) on TCP 22. Do not add a Tailscale
`ssh` rule for this path: that section controls Tailscale SSH, whose
tagged-to-user-owned restriction is why OpenSSH is used. Do not add a global
firewall rule either; the `tailscale0` rule leaves the public interface under
UFW's default-deny policy.

`loginctl enable-linger` is what keeps `herdr-agents` running across logout and
reboot, independently of SSH sessions.

Authorize the connection once from Bali:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 fu137 \
  'HERDR_SESSION=agents herdr status server --json'
ssh -o BatchMode=yes -o ConnectTimeout=5 joost@100.115.211.110 \
  'HERDR_SESSION=agents herdr status server --json'
```

No `/usr/share/omarchy` files are modified.

### j8 (Darwin)

j8 is a nix-darwin host, so the fleet profile arrives with the normal system
switch, run on the Mac:

```bash
make switch NIXNAME=j8
```

That activation writes the launchd agent, loads it, and appends Bali's fleet key
to `~/.ssh/authorized_keys`. macOS has no linger concept — a launchd *agent*
runs in the user's GUI login session, so the `agents` server starts at login and
stops at logout. Enable Remote Login (System Settings → General → Sharing →
Remote Login) and confirm the agent came up:

```bash
launchctl print "gui/$UID/org.nix-community.home.herdr-agents" | head
tail -n 20 /tmp/herdr-agents.log
```

Grant Bali (`100.113.194.113`) TCP 22 to j8 (`100.67.159.69`) in the tailnet
policy, in the same `acls` section (not `ssh`) used for fu137 and j9. Then, from
Bali:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 joost@100.67.159.69 \
  'HERDR_SESSION=agents /etc/profiles/per-user/joost/bin/herdr status server --json'
```

j8 sleeps like a normal workstation; when it is offline the mirror simply shows
that host as unreachable and the rest of the sidebar is unaffected.

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

Repeat for runners 04 and 05. fu137, j9 and j8 already have current Claude and
Codex Herdr integrations from their normal workstation profile. The exe.dev
golden image supplies the agent binaries but no credentials, so complete the
same interactive logins through
`ssh fu-herdr-dev`. Bali's existing agent configuration remains
user/chezmoi-owned. Do not copy API keys, OAuth files, or subscription
credentials into this repo.

## Verification

On every machine:

```bash
systemctl --user status herdr-agents   # on j8: launchctl print "gui/$UID/org.nix-community.home.herdr-agents"
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
ssh -o BatchMode=yes -o ConnectTimeout=5 joost@100.115.211.110 \
  'HERDR_SESSION=agents herdr status server --json'
ssh -o BatchMode=yes -o ConnectTimeout=5 joost@100.67.159.69 \
  'HERDR_SESSION=agents /etc/profiles/per-user/joost/bin/herdr status server --json'
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
herdctl gpu workspace list
herdctl j9 workspace list
herdctl j8 workspace list
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
   `provisionAgentRuntime = true`. A personal workstation whose profile already
   imports `users/herdr-fleet.nix` (anything on `users/joost/home-manager.nix`,
   NixOS, Darwin or Omarchy) only needs its `currentSystemName` added to the
   `workstationWorkers` list in that file.
3. Add one entry to `fleetNodes` in `users/herdr-fleet.nix`, including its role,
   SSH user and target, sidebar prefix, Herdr path, and control policy.
4. Evaluate and deploy both the node and Bali. Bali's generated `hosts.toml` and
   `herdctl` inventory update from the same entry.
5. Authenticate the agent CLIs locally and run the verification block above.

Upstream references: [Herdr persistence and remote access](https://herdr.dev/docs/persistence-remote/),
[Herdr integrations](https://herdr.dev/docs/integrations/), and
[herdr-mirror](https://github.com/nikok6/herdr-mirror).
