# Agent dev boxes (rondo)

Agent dev boxes run autonomous coding agents — currently
[rondo](https://github.com/sandsower/rondo), a Claude Code agent that polls
Linear for issues, opens an isolated git-worktree workspace per issue, and runs
`claude` until the work is done. rondo is an engineering preview; we run it in
the **deps + manual run** model — NixOS provides the dev box, the agent operator
sets up and launches rondo by hand (mirrors how it is tested on peterbot).

## Architecture (built for reuse)

| File | Role |
|------|------|
| `modules/agent-dev-box.nix` | Common host config (boot, nix, docker/podman, tailscale, ssh, sysctl, limits, `joost` admin). Imported by every agent host. |
| `users/agent-lib/home-manager.nix` | Shared home-manager dev profile, parameterized by git identity. The big toolset lives here once. |
| `users/<agent>/nixos.nix` | The agent's system account (username, SSH keys, password). Reused across all of that agent's machines. |
| `users/<agent>/home-manager-server.nix` | Thin: `import ../agent-lib/home-manager.nix { gitName=…; gitEmail=…; githubUser=…; }`. |
| `hosts/<agent>-NN.nix` | Thin: hardware import + `agent-dev-box` module + hostname + auto-update flake target + repoUpdater user. |
| `hosts/hardware/<agent>-NN.nix` | Per-machine disk/hardware layout. |

The runtime rondo needs (elixir/erlang/node/`@anthropic-ai/claude-code`/gh) is
**not** baked into Nix — the agent manages it with `mise`, which is on every host
via `lib/mksystem.nix` `sharedModules`. This matches Peter's working setup and
keeps version bumps out of the system rebuild.

## Add another machine for an existing agent

Example: a second box for jay (`agent-jay-02`).

1. Provision/obtain the box; capture its disk layout in
   `hosts/hardware/agent-jay-02.nix`.
2. Copy `hosts/agent-jay-01.nix` → `hosts/agent-jay-02.nix`; change
   `networking.hostName`, `services.nixosAutoUpdate.flake`, and the hardware
   import.
3. Add a `flake.nix` entry:
   ```nix
   nixosConfigurations.agent-jay-02 = mkSystem "agent-jay-02" {
     system = "x86_64-linux";
     user   = "agent-jay";   # reuse the same account
     server = true;
   };
   ```
4. `users/agent-jay/` is reused unchanged.

## Add a brand-new agent user

Example: agent `bob` with `agent-bob-01`.

1. `cp -r users/agent-jay users/agent-bob`.
2. In `users/agent-bob/nixos.nix`: rename `users.users.agent-jay` →
   `agent-bob`, set `home`, SSH keys, password hash.
3. In `users/agent-bob/home-manager-server.nix`: set `gitName` / `gitEmail` /
   `githubUser`.
4. Create `hosts/agent-bob-01.nix` (+ hardware) and the `flake.nix` entry with
   `user = "agent-bob"`.

## Per-operator rondo setup (on the box, as the agent user)

```bash
# 1. Runtime via mise (elixir/erlang/node/claude-code/gh)
cd ~/git/rondo/elixir && mise trust && mise install

# 2. Authenticate Claude Code once (OAuth — persists in ~/.claude/.credentials.json)
claude         # then /login

# 3. Linear key + clone + run (see rondo README / WORKFLOW.md)
export LINEAR_API_KEY=lin_api_...
cd ~/git/rondo && ./start_rondo.sh   # or ./bin/rondo --port 5000 <repo>/WORKFLOW.md
```

The target repo's CI gates (e.g. `mix ecto.migrate`) bring up their own service
deps via Docker, which is enabled on the box.

## Operator access (Tailscale SSH)

These boxes are reachable only over **Tailscale SSH** (public port 22 is firewalled
upstream). Tailscale SSH authorizes by the **tailnet ACL `ssh` block**, *not* by
`authorized_keys` — the local account you land on must be listed in the rule's
`users`, and your device must match `src`. The agent account (`agent-jay`) is a
service account run by the rondo systemd unit; humans operate it via their own
login + `sudo -iu agent-jay`.

To let an operator (e.g. Peter) in, the tailnet ACL needs a rule like:

```json
{
  "action": "accept",
  "src":    ["tag:devboxes", "peterpal@your-tailnet"],
  "dst":    ["tag:devboxes"],
  "users":  ["joost", "root", "peter", "agent-jay"]
}
```

- `users` must include the local account being used (`peter` for `peter@`,
  `agent-jay` for direct `jay@`/`agent-jay@`).
- `src` must include the operator's device. Tagged devboxes (e.g. peterbot) are
  already covered; a personal laptop must be added explicitly.
- The corresponding local user must exist on the host (joost is in
  `modules/agent-dev-box.nix`; per-operator users are added in the host file).

## The agent-jay-01 box

Reuses the decommissioned `github-runner-01` Hetzner CCX33 (8 vCPU / 30 GB /
220 GB, Tailscale `100.78.158.57`). Rebuilt **in place** — the disk layout is
label-based, so the hostname change does not move any mounts. Admin via
`ssh joost@100.78.158.57`; the `agent-jay` account is SSH-key-only once a key is
added to `users/agent-jay/nixos.nix`.
