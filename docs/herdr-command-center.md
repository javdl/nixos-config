# Herdr fleet: Bali command center

`bali` is the persistent Herdr command center. It runs the named `agents`
session and uses `herdr-mirror` to present workspaces from three regular nodes
and the fu137 GPU workstation in one sidebar.

```text
operator
   |
   | ssh bali
   v
bali: Herdr session "agents" + herdr-mirror
   |-- r03 --> github-runner-03 (regular)
   |-- r04 --> github-runner-04 (regular)
   |-- r05 --> github-runner-05 (regular)
   `-- gpu --> fu137            (GPU, watch-first)
```

Herdr remains host-local on every machine. Mirror streams the remote terminal
and agent state over SSH; it does not move processes to Bali. Closing the
operator's SSH client therefore leaves every server-owned pane running.

## Inventory

| Fleet name | Machine | Role | Tailscale IP | Sidebar prefix | Mirror mode |
|---|---|---|---|---|---|
| `runner03` | `github-runner-03` | regular | `100.126.150.43` | `r03` | control |
| `runner04` | `github-runner-04` | regular | `100.97.77.46` | `r04` | control |
| `runner05` | `github-runner-05` | regular | `100.108.96.124` | `r05` | control |
| `gpu` | fu137 Omarchy boot | GPU | `100.92.74.63` | `gpu` | watch-first |

Bali runs Tailscale with DNS acceptance disabled, so the declarative inventory
uses tailnet IPs rather than MagicDNS names. If a machine is re-enrolled and its
IP changes, update `fleetNodes` in `users/herdr-fleet.nix`.

The GPU mirror sets `always_control = false`: it observes without changing the
visible fu137 terminal geometry until somebody types into the mirrored pane.
The headless runners stay writable and follow the controller pane size.

## Declarative pieces

- `users/herdr-fleet.nix` is the fleet source of truth. It generates the node
  service, Bali's controller config, `hosts.toml`, and the `herdctl` helper.
- `modules/herdr-fleet-node.nix` adds a minimal `joost` Home Manager profile to
  a NixOS node while leaving the `github-runner` CI account isolated.
- `users/herdr-mirror-plugin.toml` is the local plugin manifest. The upstream
  network build step is removed because Nix supplies the verified binary.
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

That activation installs Bali's public fleet key in
`~/.ssh/authorized_keys` and starts the `agents` Herdr user service. Omarchy
already installs OpenSSH, but its daemon is not enabled by Home Manager. Enable
it once on fu137:

```bash
sudo systemctl enable --now sshd
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
integrations; Bali's existing agent configuration remains user/chezmoi-owned.
Do not copy API keys, OAuth files, or subscription credentials into this repo.

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
herdctl runner04 agent list
herdctl runner05 agent read reviewer --source recent-unwrapped --lines 120
```

`herdctl` shell-quotes all remote arguments and forces the shared `agents`
session. Use raw SSH for non-Herdr administration.

## Add a node later

1. Put the machine on the tailnet and verify Bali can use non-interactive SSH.
2. Import `modules/herdr-fleet-node.nix` from the NixOS host. For a non-NixOS
   host, import `users/herdr-fleet.nix` from its Home Manager profile with
   `provisionAgentRuntime = true`.
3. Add one entry to `fleetNodes` in `users/herdr-fleet.nix`, including its role,
   Tailscale IP, sidebar prefix, Herdr path, and control policy.
4. Evaluate and deploy both the node and Bali. Bali's generated `hosts.toml` and
   `herdctl` inventory update from the same entry.
5. Authenticate the agent CLIs locally and run the verification block above.

Upstream references: [Herdr persistence and remote access](https://herdr.dev/docs/persistence-remote/),
[Herdr integrations](https://herdr.dev/docs/integrations/), and
[herdr-mirror](https://github.com/nikok6/herdr-mirror).
