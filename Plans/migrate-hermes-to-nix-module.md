# Plan: Migrate hermes-agent on loom from install.sh → upstream NixOS module

> **Status:** draft, awaiting approval. No changes made yet. This supersedes the install.sh path documented in `add-hermes-agent.md` once approved & executed.
>
> **Audit pass complete** (see `Plans/check-the-plan-for-misty-turtle.md`). Seven fixes from that audit are now reflected in this plan: Phase 0 added (auto-update quiesce), Phase 0.5 added (git rollback anchor), Phase 3 sops snippet tightened with `owner = "hermes"`, Phase 5 reordered to remove the `~/.local/bin/hermes` shim before `nixos-rebuild switch`, Phase 6 gained a state-dir mode check, the Risks table was trimmed of speculative rows, and the Rollback section now distinguishes pre-push vs post-push scenarios.

## Context

The previous plan (`Plans/add-hermes-agent.md`) chose the upstream `install.sh` path on the assumption that hermes had no Nix-native deployment story. That assumption was wrong: `github:NousResearch/hermes-agent` ships a first-class `nixosModules.default` exposing `services.hermes-agent.*` with declarative config, secrets via `environmentFiles`, hardened systemd service, and `addToSystemPackages` to wire the CLI in.

What we have on loom **today**:
- `~/.local/bin/hermes` — a shim installed by upstream `install.sh`
- `~/.hermes/` — user-owned state (uv venv, config.yaml, .env, sessions, skills/, kanban.db, state.db, SOUL.md, cron/, hooks/, memories/)
- `users/joost/home-manager-server.nix:697-713` — hand-rolled **user-level** systemd unit `hermes-agent-gateway` running `~/.local/bin/hermes gateway run`
- No `hermes-agent` input in `flake.nix`
- Loom is **not** in `.sops.yaml`; hermes secrets live in unencrypted `~/.hermes/.env`

What we want **after**:
- `hermes-agent` flake input + module imported in `hosts/loom.nix`
- System service (`hermes:hermes`) on `/var/lib/hermes/` managed by Nix, restarted on rebuild
- Declarative model/provider/MCP config under `services.hermes-agent.settings`
- Secrets encrypted in `secrets/loom.yaml` (sops-nix, decrypted via loom's SSH host key)
- `~/.local/bin/hermes` deleted; `hermes` on `$PATH` from `/run/current-system/sw/bin/` via `addToSystemPackages = true`
- `joost` added to `hermes` group so the interactive TUI shares `HERMES_HOME` with the service
- `users/joost/home-manager-server.nix` hermes block deleted
- `Plans/add-hermes-agent.md` archived (or marked superseded)

## Decisions

| Question | Decision | Rationale / open? |
|---|---|---|
| Module path | **upstream `services.hermes-agent`** | matches docs; tracks upstream; one source of truth |
| Native vs container mode | **native** | matches current setup; container mode is for apt/pip mutability we don't need |
| `addToSystemPackages` | **true** | makes `hermes` available to `joost` shell via `$PATH`, exports `HERMES_HOME` so TUI sees the same state as the service |
| Add `joost` to `hermes` group | **yes** | required for `joost` to read/write `/var/lib/hermes/.hermes/*` from interactive shell (sessions, kanban). Without this, the TUI can't see service state |
| Secrets manager | **sops-nix** (the repo's existing pattern) | re-key once, reuse forever; `modules/secrets.nix` already wires SSH-host-key decryption |
| State migration | **copy `~/.hermes/{state.db,kanban.db,SOUL.md,cron/,memories/,skills/,hooks/}` → `/var/lib/hermes/.hermes/` then `chown -R hermes:hermes`** | sessions/ and memories/ are empty; skills/ is 8 MB; copying is cheap |
| `SOUL.md` handling | **state-dir copy (mutable)**, not declarative `documents` | Hermes self-edits SOUL.md at runtime; declarative would freeze it. Recommend status quo |
| Provider config (model, base_url) | **declarative via `settings.model.*`** | currently in `~/.hermes/config.yaml`; translate verbatim |
| Provider auth | `ANTHROPIC_API_KEY` via `environmentFiles` (sops) | matches docs; replaces current `hermes setup` interactive flow which is **blocked** in managed mode |
| Telegram gateway | preserve (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` via sops) | unchanged behavior |
| Rollback plan | **keep `~/.hermes/` intact during cutover** (copy, don't move) | if module fails to start, `systemctl stop hermes-agent && systemctl --user enable --now hermes-agent-gateway` reinstates the old path within seconds |

**Open for you to confirm before I execute:**
1. ☐ Are you OK adding `joost` to the system `hermes` group? (alternative: TUI can't see service state — basically don't use it interactively anymore)
2. ☐ Confirm declarative model is `anthropic/claude-opus-4.6` (from current `~/.hermes/config.yaml`) — leave as-is or bump?
3. ☐ Any other API keys currently in your shell env (`~/.env`?) that hermes uses and need to enter sops? (`ELEVENLABS_API_KEY`, `APIFY_TOKEN`, etc. — your existing `~/.env` pattern)

## Pre-flight facts (already verified)

- `nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"` ✅ matches hermes-agent's expectation
- Loom's age public key: `age1p26cwwyu2v4jexue6z7krrua9skqv0p3aj4ad3su4m7varky3dwqk0zphj` (derived from `/etc/ssh/ssh_host_ed25519_key.pub`)
- `modules/secrets.nix` is already imported by `hosts/loom.nix` (line 16); sops decryption will Just Work once `.sops.yaml` lists loom
- `.sops.yaml` currently has recipients for joostclaw + 2 github-runners; **loom is missing**
- `joost` user already exists; system uses `users.mutableUsers = false`, so group changes go through Nix
- State to migrate is small: state.db 100K, kanban.db 100K, skills/ 7.8M, the rest empty/4K
- `~/.hermes/config.yaml` declares `model.default = "anthropic/claude-opus-4.6"`, `provider = "auto"`, `base_url = "https://openrouter.ai/api/v1"`
- Upstream module's actual `ExecStart` is `${hermes}/bin/hermes gateway` (no `--replace`, no `run` sub-verb) — `nix/nixosModules.nix:873-876`. The docs page that says `hermes gateway run --replace` is misleading; `--replace` is added only in container mode. Native mode relies on `Restart = "always"` for stale-lock recovery.
- Upstream module creates `users.users.hermes` early enough that sops-nix's `setupSecrets` activation script runs after — `owner = "hermes"` on `sops.secrets."hermes-env"` is safe (`nix/nixosModules.nix:707`).
- Upstream module hardcodes state dir mode `2770` (group-writable + setgid), `${user}:${group}` — `nix/nixosModules.nix:732-741`. `joost ∈ hermes` group gets rwx with no further effort. There is **no** `stateDirMode` option.
- Upstream module concatenates `environmentFiles` raw into `$HERMES_HOME/.env` — `nix/nixosModules.nix:752-756`. Hermes parses it as dotenv at startup, not systemd as `EnvironmentFile=`. Quoting rules follow dotenv.

## Implementation

Phases are committable units. **Each phase ends with `make test NIXNAME=loom` passing (and where noted, `make switch NIXNAME=loom`).** Plan-mode means we stop after writing this doc — actual execution is a separate user-approved session.

### Phase 0 — Quiesce auto-update (runtime, on loom, BEFORE Phase 3 commit lands on `main`)

`hosts/loom.nix:59-65` enables `services.nixosAutoUpdate` with `dates = "04:00"` ± 30 min. If the migration commit hits `main` and the timer fires before Phase 5 runs, the service will start with an empty `/var/lib/hermes/.hermes/` before any human can rsync state in. Mask the timer to make execution synchronous with the operator:

```bash
sudo systemctl stop nixos-upgrade.timer
sudo systemctl mask nixos-upgrade.timer    # survives reboot until unmasked
systemctl is-enabled nixos-upgrade.timer   # → masked (verify)
```

After Phase 6 verification passes:

```bash
sudo systemctl unmask nixos-upgrade.timer
sudo systemctl start nixos-upgrade.timer
```

If you forget to mask: the next scheduled rebuild *will* fire with the new config and start the service against an empty state dir. Recoverable (stop service, rsync state, restart) but loud and harder to diagnose at 4 AM.

### Phase 0.5 — Tag a rollback anchor

Single command, in this repo on whatever machine is doing the Nix edits:

```bash
git tag pre-hermes-migration HEAD
git push origin pre-hermes-migration   # makes the anchor available from loom too
```

Used by the Rollback section's Scenario B.

### Phase 1 — Wire the flake input + sops recipient (no service yet)

Files touched: `flake.nix`, `.sops.yaml`.

1. **Add input** to `flake.nix`:
   ```nix
   inputs.hermes-agent = {
     url = "github:NousResearch/hermes-agent";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```
2. **No `outputs` destructuring change needed.** The existing `...@inputs:` capture at `flake.nix:68` already includes the new input, and `lib/mksystem.nix:93-99` threads `inputs` into every host module via `config._module.args` — confirmed during audit. The hermes module is reachable as `inputs.hermes-agent.nixosModules.default`.
3. **Add loom to `.sops.yaml`:**
   ```yaml
   - &loom age1p26cwwyu2v4jexue6z7krrua9skqv0p3aj4ad3su4m7varky3dwqk0zphj

   creation_rules:
     - path_regex: secrets/loom\.yaml$
       key_groups:
         - age:
             - *loom
   ```
4. **Verify:** `make test NIXNAME=loom` evaluates clean (no service exists yet; just input resolution).

**Commit:** `feat(hermes): add flake input + sops recipient for loom`

### Phase 2 — Encrypt secrets

Files touched: `secrets/loom.yaml` (new, encrypted).

1. On joostclaw, decrypt the existing `ironclaw-anthropic-api-key` and `ironclaw-telegram-bot-token` (per the earlier plan's step 2).
2. From loom, run:
   ```bash
   sops secrets/loom.yaml
   ```
   File contents (plaintext editor view, sops re-encrypts on save):
   ```yaml
   hermes-env: |
     ANTHROPIC_API_KEY=sk-ant-...
     TELEGRAM_BOT_TOKEN=...:...
     TELEGRAM_ALLOWED_USERS=<your numeric telegram user id>
     # Optionally: OPENROUTER_API_KEY, ELEVENLABS_API_KEY, APIFY_TOKEN, etc.
     # (whatever else is in current ~/.hermes/.env or ~/.env that hermes uses)
   ```

   **Format note:** the decrypted plaintext of `hermes-env` is `cat`'d raw into `$HERMES_HOME/.env` by the module (`nix/nixosModules.nix:752-756`), then parsed by hermes as **dotenv**, not by systemd as `EnvironmentFile=`. Dotenv quoting rules apply: values with `#`, spaces, or newlines need quoting; no `export ` prefix; one assignment per line. `KEY=VALUE` is always safe.

3. Verify on loom: `sops -d secrets/loom.yaml | head -1` → first line of decrypted payload.

**Commit:** `feat(hermes): encrypt loom hermes-env secrets`

### Phase 3 — Add the system service (gated, not yet replacing the user unit)

Files touched: `hosts/loom.nix`.

Add to `hosts/loom.nix`:

```nix
# Top of file: import the module from the flake input.
# `inputs` is threaded into hosts via lib/mksystem.nix; add it to the function args.

{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware/loom.nix
    ../modules/cachix.nix
    ../modules/secrets.nix
    # … existing imports …
    inputs.hermes-agent.nixosModules.default
  ];

  # Sops secret for hermes. owner = "hermes" is safe: the upstream module's
  # activation script depends on ["users", "setupSecrets"] (nix/nixosModules.nix:707),
  # so the hermes user exists when sops-nix chowns the decrypted file.
  sops.secrets."hermes-env" = {
    sopsFile = ../secrets/loom.yaml;
    format = "yaml";
    key = "hermes-env";
    owner = "hermes";
    mode = "0400";
  };

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;

    environmentFiles = [ config.sops.secrets."hermes-env".path ];

    settings.model = {
      default = "anthropic/claude-opus-4.6";
      provider = "auto";
      base_url = "https://openrouter.ai/api/v1";
    };

    # joost shares HERMES_HOME via group membership (see below)
  };

  users.users.joost.extraGroups = [ "hermes" ];
}
```

**`inputs` threading verified** in audit (`lib/mksystem.nix:93-99` sets `config._module.args.inputs = inputs;`). No `mksystem.nix` change needed.

1. `make test NIXNAME=loom` — should evaluate clean.
2. **Don't switch yet** — the user-level unit from home-manager-server.nix would race with this. Either:
   - First disable the user unit (`systemctl --user disable --now hermes-agent-gateway`) on the live host, then `make switch`, **or**
   - Combine this phase with Phase 4 so the user unit is removed in the same commit/switch.

Recommend the combined approach (Phase 3 + 4 together) to avoid a transient state.

**Commit:** `feat(hermes): adopt upstream NixOS module on loom` (combined with Phase 4 below)

### Phase 4 — Remove the home-manager user unit

Files touched: `users/joost/home-manager-server.nix`.

Delete lines 678-713 (the entire `# Hermes Agent gateway` comment block + `systemd.user.services.hermes-agent-gateway` definition).

**Commit (combined with Phase 3):** `feat(hermes): adopt upstream NixOS module on loom`

### Phase 5 — Switch & migrate state

This phase is **runtime work on loom**, no Nix changes. Run interactively — order matters:

```bash
# 0. Sanity: confirm Phase 0 quiesce is still in effect
systemctl is-enabled nixos-upgrade.timer   # → masked (must NOT be enabled)

# 1. Stop the old user-level service (it still exists in current generation)
systemctl --user stop hermes-agent-gateway
systemctl --user disable hermes-agent-gateway

# 2. Remove the install.sh shim BEFORE switch so the new system PATH wins immediately.
#    If left in place and ~/.local/bin is on PATH ahead of /run/current-system/sw/bin
#    (common in zsh), the interactive TUI would still run against ~/.hermes/ and miss
#    the new HERMES_HOME export. The ~/.hermes/ DATA dir is preserved for rollback;
#    only the launcher script goes.
rm -f ~/.local/bin/hermes

# 3. Apply the new generation (creates hermes user, /var/lib/hermes, starts service —
#    will start with an EMPTY .hermes/ at this point)
sudo nixos-rebuild switch --flake .#loom

# 4. The service will start and bootstrap a fresh /var/lib/hermes/.hermes/.
#    Stop it immediately so we can overlay our existing state:
sudo systemctl stop hermes-agent

# 5. Migrate state (preserves sessions, kanban, SOUL.md, skills, cron jobs)
sudo rsync -a --info=progress2 \
  ~/.hermes/state.db \
  ~/.hermes/kanban.db \
  ~/.hermes/SOUL.md \
  ~/.hermes/cron/ \
  ~/.hermes/memories/ \
  ~/.hermes/skills/ \
  ~/.hermes/hooks/ \
  ~/.hermes/sessions/ \
  /var/lib/hermes/.hermes/

# 6. Fix ownership (and let setgid bit on the parent dir handle group inheritance)
sudo chown -R hermes:hermes /var/lib/hermes/.hermes/

# 7. Verify the `.managed` marker is present (module creates it):
ls -la /var/lib/hermes/.hermes/.managed

# 8. Restart
sudo systemctl start hermes-agent
sudo systemctl status hermes-agent
journalctl -u hermes-agent -n 50 --no-pager
```

### Phase 6 — Verify

```bash
# Service running
systemctl is-active hermes-agent                          # → active
journalctl -u hermes-agent -n 20 --no-pager | grep -iE 'error|warn' || echo "no errors"

# State dir has the hardcoded mode/group from the upstream module
stat -c '%a %U:%G' /var/lib/hermes/.hermes                # → 2770 hermes:hermes
sudo -u joost test -r /var/lib/hermes/.hermes/state.db \
  && echo "joost group access OK" || echo "FAIL: re-check joost ∈ hermes"

# CLI available system-wide and points at managed state
which hermes                                              # → /run/current-system/sw/bin/hermes
hermes version                                            # → >= 0.13.x
echo "$HERMES_HOME"                                       # → /var/lib/hermes/.hermes
hermes config | head                                      # should match declarative settings

# Interactive TUI sees service state (because joost ∈ hermes group + HERMES_HOME exported)
hermes                                                    # TUI starts, shows existing kanban + sessions

# Telegram smoke test
# Send "hi" to the bot from the whitelisted Telegram account → bot replies

# All green? Release the timer mask from Phase 0.
sudo systemctl unmask nixos-upgrade.timer
sudo systemctl start nixos-upgrade.timer
systemctl is-enabled nixos-upgrade.timer                  # → enabled
```

### Phase 7 — Cleanup

Once Phase 6 passes and you've used the service for ~24h with no surprises:

```bash
# The ~/.local/bin/hermes shim was already removed in Phase 5 step 2.
# Move (don't delete yet) the old state dir as a backup
mv ~/.hermes ~/.hermes.preNixModule.$(date +%Y%m%d)

# After another week without issues:
rm -rf ~/.hermes.preNixModule.*

# Optional: drop the rollback anchor
git tag -d pre-hermes-migration
git push origin :refs/tags/pre-hermes-migration
```

Mark `Plans/add-hermes-agent.md` superseded (add a header note) or move it to `Plans/archive/`.

**Commit:** `chore(hermes): retire install.sh path` (only Plans/ changes; runtime cleanup is local)

## Rollback

Phase 5 **copies** state (not moves), and Phase 5 step 2 only removes the launcher shim, not the `~/.hermes/` data dir. So `~/.hermes/` is intact for rollback at every step.

This repo is `jj`-on-top-of-git (`.jj/` and `.git/` both present). `jj op restore` rewinds the local working copy but **does NOT rewrite refs on `origin`**. The rollback path therefore depends on whether the migration commit was already pushed.

### Scenario A — failure detected BEFORE pushing Phase 3-4 commit

```bash
# 1. Stop the new service if it started
sudo systemctl stop hermes-agent
sudo systemctl disable hermes-agent

# 2. Restore working copy
jj op log                              # find the pre-migration operation id
jj op restore <op-id-before-phase-3>

# 3. Re-apply the prior generation (this restores the user-level unit)
sudo nixos-rebuild switch --flake .#loom

# 4. Re-enable the old user unit
systemctl --user daemon-reload
systemctl --user enable --now hermes-agent-gateway

# 5. Reinstate the install.sh shim (only if you also removed it in Phase 5 step 2)
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
  | bash -s -- --skip-setup
```

### Scenario B — failure detected AFTER pushing Phase 3-4 commit

Two options. Prefer the revert-commit path (B1) — it's auditable and doesn't rewrite history. Only use B2 if no other commits have landed on `main` since the migration.

**B1: Revert via new commit (default)**

```bash
sudo systemctl stop hermes-agent
sudo systemctl disable hermes-agent

# Create a revert commit on top of main
jj new main
jj backout <migration-commit-id>       # or manually edit out the hermes changes
jj bookmark set main -r @
jj git push

# Apply the reverted state on loom
sudo nixos-rebuild switch --flake github:javdl/nixos-config#loom

# Reinstate the old user unit + shim (see Scenario A steps 4-5)
```

**B2: Hard-reset `main` (only when no other commits depend on the migration)**

```bash
sudo systemctl stop hermes-agent
sudo systemctl disable hermes-agent

# Phase 0.5 already created the anchor tag; use it
git reset --hard pre-hermes-migration
git push --force-with-lease origin main

# Apply on loom
sudo nixos-rebuild switch --flake github:javdl/nixos-config#loom

# Reinstate the old user unit + shim (see Scenario A steps 4-5)
```

In either scenario, **don't forget to `sudo systemctl unmask nixos-upgrade.timer`** if Phase 6 didn't complete (Phase 0 masked it).

## Out of scope

- **Other hosts.** Plan covers loom only. Replicating to j7/j8/fu137 requires a separate decision (workstations use `home-manager.nix`, not server flavor; the module is system-level, which means each host's `hosts/<name>.nix` opts in).
- **Container mode.** `services.hermes-agent.container.enable = true` is interesting if we later want apt/pip mutability inside the agent's sandbox; not needed now.
- **`documents.SOUL.md` declarative path.** Would force-overwrite SOUL.md on every switch, breaking Hermes' ability to self-edit its persona. Punt.
- **Renaming `ironclaw-*` keys in `secrets/joostclaw.yaml`.** Inert; doesn't affect loom. Already out of scope in prior plan.

## Risks & mitigations

The audit eliminated four speculative risks (inputs threading, sops/perms, `environmentFiles` format, state-dir mode) by reading the upstream module source and `lib/mksystem.nix`. Surviving risks:

| Risk | Mitigation |
|---|---|
| State migration race (Hermes mid-write during rsync) | Phase 5 step 4 stops the service before step 5 rsync; service is single-writer, so once stopped, files are quiescent |
| Anthropic key in `~/.hermes/.env` was never actually set (current provider is "auto" and may live off `~/.env`) | Phase 2 covers this: audit `~/.hermes/.env` AND shell env before encrypting; include every key hermes actually reads |
| nixosAutoUpdate fires mid-migration and starts the service against an empty state dir | **Phase 0** masks `nixos-upgrade.timer` before Phase 3 commits hit `main`; Phase 6 unmasks it after verification |
| `~/.local/bin/hermes` shim shadows the Nix-installed binary in zsh, making the interactive TUI hit the old state dir | **Phase 5 step 2** removes the shim before `nixos-rebuild switch`, so the new system PATH wins on first use |
| Rollback impossible because the migration commit was already on `origin/main` | **Phase 0.5** tags `pre-hermes-migration` BEFORE any push; Rollback Scenario B uses it for either a revert-commit or force-reset path |

## Estimated effort

- Phase 0 + 0.5: 2 min (timer mask + git tag)
- Phase 1-2: 20 min (input + sops setup)
- Phase 3-4: 30 min (writing & testing module config)
- Phase 5: 10 min (mostly waiting for nixos-rebuild)
- Phase 6: 15 min (verification including Telegram + timer unmask)
- Phase 7: 5 min plus a ~week soak

**Total active time: ~85 min spread across two sittings (today + cleanup next week).**
