# Herdr fleet: Bali command center

`bali` is the persistent Herdr command center. It runs the named `agents`
session and uses `herdr-mirror` to present workspaces from three regular
runners, the fu137 GPU workstation, and a maximum-size exe.dev development VM
in one sidebar.

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
| `gpu` | fu137 Omarchy boot | GPU | `100.92.74.63` | `gpu` | watch-first |
| `exedev` | `fu-herdr-dev` | dev | `fu-herdr-dev` SSH alias | `exe` | control |

Bali runs Tailscale with DNS acceptance disabled, so tailnet nodes use IPs
rather than MagicDNS names. The exe.dev worker uses the dotless
`fu-herdr-dev` SSH alias, which selects Bali's FashionUnited team key without
matching its personal `*.exe.xyz` block. If a tailnet machine is re-enrolled
and its IP changes, update `fleetNodes` in `users/herdr-fleet.nix`.

The GPU mirror sets `always_control = false`: it observes without changing the
visible fu137 terminal geometry until somebody types into the mirrored pane.
The headless runners and exe.dev worker stay writable and follow the controller
pane size.

The three runners are NixOS and accept Bali over OpenSSH. fu137 is Arch/Omarchy
and instead uses **Tailscale SSH**: no `sshd`, no `authorized_keys` entry, and
no open port 22. See [First rollout](#first-rollout) for why, and note that
fu137 is a worker only. It never runs `herdr-mirror`; the mirror package,
`hosts.toml`, and plugin activation are all gated on `controller`, which fu137
does not set.

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
- `users/joost/home-manager.nix` enables node mode on fu137 without touching
  Omarchy-owned desktop, terminal, Hyprland, or package configuration.

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

Apply the standalone Home Manager output on fu137:

```bash
make switch NIXNAME=fu137
```

That activation starts the `agents` Herdr user service. It installs no SSH key:
fu137 is reached over **Tailscale SSH**, not OpenSSH.

```bash
sudo tailscale set --ssh
sudo loginctl enable-linger joost
loginctl show-user joost -p Linger
```

Tailscale SSH terminates the connection inside `tailscaled` and authorizes it
from tailnet identity and the tailnet SSH ACL, so it needs neither an
`~/.ssh/authorized_keys` entry nor a listening port. Consequences, all
deliberate:

- **`users/herdr-fleet.nix` must not declare `home.file.".ssh/authorized_keys"`
  for fu137.** Home Manager would replace the user-owned live file with a
  read-only Nix store symlink and drop every other key already trusted on the
  machine. The live file stays hand-managed.
- **Do not run `systemctl enable sshd` on fu137.** Omarchy ships OpenSSH but
  leaves the daemon disabled; enabling it creates a second, redundant network
  listener that Tailscale SSH already makes unnecessary.
- **Do not open port 22 in the firewall.** fu137's UFW default-deny input
  policy stays as-is; no rule, interface-scoped or otherwise, is added. Nothing
  new is exposed on the public interface.

`loginctl enable-linger` is what keeps `herdr-agents` running across logout and
reboot, since Tailscale SSH sessions do not hold the user manager open.

Authorize the connection once from Bali:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 joost@100.92.74.63 \
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
for ip in 100.126.150.43 100.97.77.46 100.108.96.124 100.92.74.63; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 "joost@$ip" \
    'HERDR_SESSION=agents herdr status server --json'
done
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
