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

## rondo systemd service

`hosts/agent-jay-01.nix` defines a `rondo` systemd unit that runs the agent
unattended (runner-style): `User=agent-jay`, runtime via `mise`, `Restart=on-failure`,
`LINEAR_API_KEY` injected from SOPS (`sops.templates."rondo.env"` →
`/run/secrets/rendered/rondo.env`). It replicates the operator's working command:
`mise exec -- ./bin/rondo --i-understand-… --port 5000 ~/git/api/WORKFLOW.md`.

The unit is **guarded** by `ConditionPathExists` on both `~/git/rondo/elixir/bin/rondo`
and `~/git/api/WORKFLOW.md`, so it stays dormant (no crash-loop) until the one-time
bring-up below is done. After bring-up: `sudo systemctl start rondo`,
`journalctl -u rondo -f`.

## One-time bring-up (on the box, as the agent user)

The runtime + checkout live in the agent's home (deps+manual model), not in Nix.
Run as `agent-jay` (`sudo -iu agent-jay`):

```bash
# 1. Clone + build rondo. The runtime (erlang OTP 28 + elixir 1.19.5, node) comes
#    from nixpkgs in the agent profile — NOT mise: mise compiles erlang from source
#    (kerl) which fails on NixOS (no ncurses/openssl in /usr). Build with plain mix.
mkdir -p ~/git && git clone https://github.com/sandsower/rondo.git ~/git/rondo
cd ~/git/rondo/elixir && mix setup && mix build

# 2. beislid action-policy stub (rondo calls `beislid`; the stub always allows)
#    — install to ~/.local/bin/beislid (see the script in this repo's history / Peter's setup)

# 3. Claude Code auth — one-time, INTERACTIVE (browser device-code):
claude          # then /login   (persists in ~/.claude/.credentials.json)
#    Optionally keep multiple Max logins warm and rotate with `caam`
#    (installed): `caam backup claude <profile>` per account, then `caam` to switch.

# 4. GitHub access for agent-jay (rondo clones each issue's repo via SSH):
#    add a machine/deploy SSH key to ~/.ssh + register it on GitHub, then clone the
#    tracker's target repo + its WORKFLOW.md, e.g. ~/git/api/WORKFLOW.md.

# 5. (Optional) Linear MCP for the Claude sessions rondo spawns:
#    rondo already serves a client-side `linear_graphql` tool from $LINEAR_API_KEY;
#    add the Linear MCP server only if richer Linear ops are needed.
```

The target repo's CI gates (e.g. `mix ecto.migrate`) bring up their own service
deps via Docker, which is enabled on the box. Once steps 1–4 are done the
`ConditionPathExists` guards pass and `systemctl start rondo` runs it under systemd.

## Tailscale tag

Agent boxes must be **`tag:devboxes`** so the tailnet's devbox grants/ssh rules
apply (agent mesh, and `group:it`/`group:devbox-users` SSH access as
`autogroup:nonroot`). `modules/agent-dev-box.nix` self-declares it via
`--advertise-tags=tag:devboxes`, which only takes effect at first auth — so the
**provisioning authkey must be authorized for `tag:devboxes`** (tag owners:
`group:it`, `group:management`). A box reused from another tag (e.g. agent-jay-01
came from `tag:github-runner`) must be retagged once in the admin console
(Machines → host → Edit ACL tags); the self-tag then keeps fresh provisions
correct.

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

**Connecting** (once the ACL grants you): connect from a device that authenticates
as your *user* identity (e.g. a personal laptop), not a tagged devbox (those only
match the `joost`/`root` tag→tag rule):

```bash
ssh peter@agent-jay-01          # then: sudo -iu agent-jay   (operate the agent account)
ssh agent-jay@agent-jay-01      # or land on the agent account directly
```

Group `group:it`/`group:devbox-users` members already match the devbox `check`
rule (`autogroup:nonroot`), so they can land as `peter` or `agent-jay` after a
one-time browser re-auth.

## MCP servers

agent-jay's Claude config (`~/.claude.json`, user scope) has both servers wired
headless (no interactive OAuth):
- **linear** → `https://mcp.linear.app/mcp`, `Authorization: Bearer $LINEAR_API_KEY`
- **github** → `https://api.githubcopilot.com/mcp/`, `Authorization: Bearer <PAT>`

Add/re-add with `claude mcp add --scope user --transport http <name> <url> --header "Authorization: Bearer <token>"`.
Note: if **caam** swaps `~/.claude`, re-check the servers survive the switch. The
`gh` CLI needs a PAT with `repo` + `read:org` (the MCP itself does not).

## The agent-jay-01 box

Reuses the decommissioned `github-runner-01` Hetzner CCX33 (8 vCPU / 30 GB /
220 GB, Tailscale `100.78.158.57`). Rebuilt **in place** — the disk layout is
label-based, so the hostname change does not move any mounts. Admin via
`ssh joost@100.78.158.57`; the `agent-jay` account is SSH-key-only once a key is
added to `users/agent-jay/nixos.nix`.
