# Audit: `Plans/migrate-hermes-to-nix-module.md`

## Context

The migration plan at `Plans/migrate-hermes-to-nix-module.md` proposes swapping loom's `install.sh`-based hermes-agent setup for the upstream `services.hermes-agent` NixOS module. Before executing, I verified its load-bearing assumptions against (a) the actual Nix wiring in this repo, (b) the upstream module source, and (c) loom-specific runtime concerns. The audit confirms most claims and surfaces **one real bug**, **two corrections to factual claims**, and **three procedural tightenings**. Each is small; the migration's overall shape is sound.

This file is the audit deliverable. The fixes below should be applied to `Plans/migrate-hermes-to-nix-module.md` in a follow-up session (this session is plan-mode read-only).

---

## ✅ Verified correct (no changes needed)

These three claims in the migration plan are accurate; I include them so they are not re-litigated:

1. **`inputs` is threaded into host modules.** `lib/mksystem.nix:93-99` sets `config._module.args.inputs = inputs;`. The migration plan's `{ config, pkgs, lib, inputs, ... }:` signature for `hosts/loom.nix` will work as written.
2. **sops-nix module is already globally imported.** `lib/mksystem.nix:63` conditionally adds `inputs.sops-nix.nixosModules.sops` to the module list for non-Darwin systems. Existing usage at `hosts/joostclaw.nix:208` and `hosts/github-runner-01.nix:240-243` confirms `sops.secrets.*` works without further plumbing.
3. **`users.users.joost.extraGroups = [ "hermes" ]` merges additively.** Current joost groups are `[ "docker" "wheel" ]` at `users/joost/nixos.nix:14-26`; NixOS concatenates `extraGroups` lists across modules unless `mkForce` is used. The hermes group is created at activation by the upstream module's `createUser = true`, so eval-time ordering doesn't matter.

---

## 🔴 Critical bug — must be fixed before executing

### A1. `nixosAutoUpdate` will race the state migration

**Where:** `Plans/migrate-hermes-to-nix-module.md`, Risk table row "make switch from a workstation…" and Phase 5 (runtime work).

**The problem:** `hosts/loom.nix:59-65` enables `services.nixosAutoUpdate` with `dates = "04:00"` ± 30 min randomized delay. `modules/nixos-auto-update.nix:90-104` runs:
```
nixos-rebuild switch --no-write-lock-file -L --refresh --flake github:javdl/nixos-config#loom --upgrade
```
If the migration commit is pushed to `main` at, say, 22:00, the auto-update timer fires at ~04:00 and **activates the new generation autonomously** — `hermes-agent` will start with an empty `/var/lib/hermes/.hermes/` before any human has rsync'd state from `~/.hermes/`. Result: hermes loses session history, kanban, SOUL.md, and skills/ until manual recovery.

The migration plan's current workflow ("push to main first, then `nixos-rebuild switch`") implicitly assumes the operator immediately runs Phase 5 after pushing. There is no enforcement.

**Fix to apply to the migration plan — add a new Phase 0:**

```markdown
### Phase 0 — Quiesce auto-update (runtime, on loom, before Phase 3 commit lands on `main`)

sudo systemctl stop nixos-upgrade.timer
sudo systemctl mask nixos-upgrade.timer    # survives reboot until unmasked

After Phase 6 verification passes:
sudo systemctl unmask nixos-upgrade.timer
sudo systemctl start nixos-upgrade.timer

If you forget to mask: the next scheduled rebuild *will* fire with the new
config and start the service against an empty state dir. This is recoverable
(stop service, rsync state, restart) but loud.
```

**Also update Phase 5** to verify the timer is masked before proceeding (`systemctl is-enabled nixos-upgrade.timer` should report `masked`).

---

## 🟡 Factual corrections (claims in the plan that are wrong-but-non-fatal)

### B1. Plan's audit summary says docs prescribe `ExecStart: hermes gateway run --replace`. Upstream module's actual ExecStart is `hermes gateway` (no `--replace`).

**Where:** `Plans/migrate-hermes-to-nix-module.md`, "Context" section table row "Entry command" — and the parent comparison in my prior turn.

**Ground truth:** `nix/nixosModules.nix` lines 873-876 of the upstream module:
```nix
ExecStart = lib.concatStringsSep " " ([
  "${effectivePackage}/bin/hermes"
  "gateway"
] ++ cfg.extraArgs);
```
`--replace` is only added in **container** mode, not native. The docs page is misleading.

**Fix:** Update the comparison table in the migration plan's Context section to read `hermes gateway` (no `--replace`). If the user actually wants `--replace` behavior (e.g., to forcibly take over a stale lock), add `services.hermes-agent.extraArgs = [ "--replace" ];` to the module config in Phase 3 — recommend NOT adding it by default, since the module's systemd unit already handles restarts via `Restart = "always"`.

### B2. Plan implies `hermes` user might not exist when sops-nix runs

**Where:** `Plans/migrate-hermes-to-nix-module.md`, Phase 3 code comment "`owner default = root; hermes service reads it via systemd LoadCredential or…`" and Risk table row "Module's `environmentFiles` expects different file perms than sops default".

**Ground truth:** `nix/nixosModules.nix:707` registers the hermes-agent activation script with `lib.stringAfter ([ "users" ] ++ lib.optional (… ? setupSecrets) "setupSecrets")`. NixOS creates `users.users.hermes` via standard `users` activation; sops-nix's `setupSecrets` runs after users. So **`owner = "hermes"` on `sops.secrets."hermes-env"` is safe** — no ordering cycle, and the file will be readable by the service.

**Fix:** In Phase 3, change the sops snippet to:
```nix
sops.secrets."hermes-env" = {
  sopsFile = ../secrets/loom.yaml;
  format = "yaml";
  key = "hermes-env";          # explicit
  owner = "hermes";            # safe; user exists at sops-nix activation
  mode = "0400";
};
```
Remove the comment that handwaves the issue.

### B3. Plan's `environmentFiles` claim is correct, but for the wrong reason

**Where:** `Plans/migrate-hermes-to-nix-module.md`, Risk table.

**Ground truth:** `nix/nixosModules.nix:752-756` activation script literally `cat`s each `environmentFiles` path into `$HERMES_HOME/.env` — raw concatenation, no parsing. So as long as the decrypted plaintext is shell-env-style (`KEY=VALUE\n` lines), it works. The sops yaml `format` with a multiline-string value produces exactly that.

**Fix:** Add a one-line note in the secrets file format example clarifying the file is concatenated raw — not parsed by systemd as an `EnvironmentFile=` would be (e.g., quoting rules differ: hermes reads it as dotenv, not systemd-env).

---

## 🟠 Procedural tightenings (gaps that aren't bugs but could surprise the operator)

### C1. State directory mode is `2770` — confirmed working, but plan should say so explicitly

**Where:** Risk table row "joost can't read /var/lib/hermes/.hermes/ despite group" notes "Verify mode bits are `g+rX`; if not, set via `services.hermes-agent.stateDirMode` if exposed".

**Ground truth:** `nix/nixosModules.nix:732-741` hardcodes:
```nix
systemd.tmpfiles.rules = [
  "d ${cfg.stateDir}            2770 ${cfg.user} ${cfg.group} - -"
  "d ${cfg.stateDir}/.hermes    2770 ${cfg.user} ${cfg.group} - -"
];
```
Mode `2770` = `drwxrwx---` plus setgid. Group members (`joost ∈ hermes`) get rwx; new files inherit the `hermes` group. **There is no `stateDirMode` option** — the value is hardcoded. The plan's risk is non-existent, but the plan currently leaves it as an open question.

**Fix:** Replace that risk row with a positive verification step in Phase 6: `stat -c '%a' /var/lib/hermes/.hermes` returns `2770`. Delete the speculative "set via `stateDirMode` if exposed" suggestion.

### C2. PATH ordering: `~/.local/bin/hermes` may shadow the Nix-installed binary in zsh

**Where:** Phase 6 verification step `which hermes # → /run/current-system/sw/bin/hermes`, Phase 7 cleanup step `rm -f ~/.local/bin/hermes`.

**The problem:** When `addToSystemPackages = true`, the module installs `hermes` at `/run/current-system/sw/bin/hermes` and exports `HERMES_HOME` via `environment.variables.HERMES_HOME` (confirmed `nixosModules.nix:485-488`). But many user zsh setups prepend `~/.local/bin` to `$PATH` — if `~/.local/bin/hermes` (the install.sh shim) still exists, it wins. The shim points at `~/.hermes/`, not `/var/lib/hermes/.hermes/`, so the user's interactive TUI would run against stale state even though the service runs correctly.

**Fix:** Reorder Phase 7 — move `rm -f ~/.local/bin/hermes` to **before** Phase 6's `which hermes` verification, or split: delete the shim in Phase 5 step 0 (alongside stopping the user unit), then verify in Phase 6. New ordering for Phase 5:
1. `systemctl --user stop hermes-agent-gateway`
2. `systemctl --user disable hermes-agent-gateway`
3. **`rm -f ~/.local/bin/hermes`** *(NEW)*
4. `sudo nixos-rebuild switch …`
5. `sudo systemctl stop hermes-agent`
6. rsync state into `/var/lib/hermes/.hermes/`
7. `sudo chown -R hermes:hermes …`
8. `sudo systemctl start hermes-agent`

The `~/.hermes/` data dir is *not* deleted in this step (still preserved for rollback); only the shim binary goes.

### C3. `jj op restore` rollback won't work alone if the commit was pushed

**Where:** Rollback section.

**Ground truth:** `/home/joost/nixos-config/.jj/` and `/home/joost/nixos-config/.git/` both exist — repo is jj-on-top-of-git. `jj op restore` rewinds the local jj op log but does NOT rewrite git refs on the remote. If Phase 3-4 commits have already been pushed to `main` (the migration plan's workflow assumes this, since `nixosAutoUpdate` pulls from `github:javdl/nixos-config#loom`), then `jj op restore` alone leaves `origin/main` ahead.

**Fix:** Replace the rollback section with two scenarios:

```markdown
## Rollback

### Scenario A — failure detected BEFORE pushing Phase 3-4 commit
jj op log
jj op restore <op-id-before-phase-3>
# Working copy is now clean; no further action needed.

### Scenario B — failure detected AFTER pushing
# Either revert via a new commit:
jj new main
# Edit out the hermes changes manually OR jj backout the migration commit
jj git push

# Or, if you must hard-reset the remote (only if no other commits have landed):
git tag pre-hermes-migration <pre-migration-sha>   # belt-and-suspenders backup
git push origin pre-hermes-migration
git reset --hard pre-hermes-migration
git push --force-with-lease origin main

# In either case, on loom:
sudo systemctl stop hermes-agent
sudo systemctl disable hermes-agent
sudo nixos-rebuild switch --flake github:javdl/nixos-config#loom
systemctl --user daemon-reload
systemctl --user enable --now hermes-agent-gateway
```

Add a "Phase 0.5" suggestion: before Phase 3, run `git tag pre-hermes-migration HEAD` to make rollback explicit.

---

## Files that will be modified by the migration (for the eventual edit session)

These paths are unchanged from the original plan; listing for traceability:

- `flake.nix` — add `inputs.hermes-agent` (Phase 1)
- `.sops.yaml` — add loom recipient + `secrets/loom.yaml` creation rule (Phase 1)
- `secrets/loom.yaml` (new, encrypted) — `hermes-env` payload (Phase 2)
- `hosts/loom.nix` — import module, declare `services.hermes-agent.*`, sops secret, add joost to hermes group (Phase 3)
- `users/joost/home-manager-server.nix` — delete lines 678-713 (Phase 4)

The upstream NixOS module is at `inputs.hermes-agent.nixosModules.default` — `github:NousResearch/hermes-agent/nix/nixosModules.nix:707-756, 873-876, 485-488, 732-741` are the key spans (referenced above).

---

## Verification of the (corrected) plan

The corrected migration plan can be verified end-to-end as follows once executed:

```bash
# Before any edits
git tag pre-hermes-migration HEAD                          # rollback anchor
sudo systemctl mask nixos-upgrade.timer                    # quiesce auto-update on loom

# After Phases 1-4 are committed and Phase 5 runtime work completes
systemctl is-active hermes-agent                           # → active
stat -c '%a %U:%G' /var/lib/hermes/.hermes                 # → 2770 hermes:hermes
sudo -u joost test -r /var/lib/hermes/.hermes/state.db && echo OK   # group access works
which hermes                                                # → /run/current-system/sw/bin/hermes
echo "$HERMES_HOME"                                         # → /var/lib/hermes/.hermes
hermes config | grep -E 'model:|default:'                   # matches services.hermes-agent.settings
journalctl -u hermes-agent -n 50 --no-pager | grep -iE 'error|exception' || echo "no errors"

# Telegram smoke test
# Send "hi" from whitelisted account → bot replies

# Finalize
sudo systemctl unmask nixos-upgrade.timer
sudo systemctl start nixos-upgrade.timer
```

If any verification fails, follow Rollback Scenario A or B above.

---

## Summary of changes the migration plan needs

| # | Type | Location in `migrate-hermes-to-nix-module.md` | Action |
|---|---|---|---|
| A1 | 🔴 bug | Risks table + Phase 5 prologue | Insert **Phase 0**: mask `nixos-upgrade.timer` before push; unmask after Phase 6 |
| B1 | 🟡 fact | "Context" comparison table | Change `hermes gateway run --replace` → `hermes gateway` |
| B2 | 🟡 fact | Phase 3 sops snippet + Risks row | Set `owner = "hermes"; mode = "0400";` and remove the "expects different perms" risk |
| B3 | 🟡 fact | Phase 2 secrets format note | Add one-liner: file is concatenated raw, not parsed by systemd |
| C1 | 🟠 gap | Risks row "joost can't read…" | Replace risk with positive verification: `stat -c '%a' /var/lib/hermes/.hermes` = `2770` |
| C2 | 🟠 gap | Phase 5 step order | Move `rm -f ~/.local/bin/hermes` from Phase 7 to Phase 5 step 3 (before `nixos-rebuild switch`) |
| C3 | 🟠 gap | Rollback section | Add Scenario A / Scenario B split; recommend `git tag pre-hermes-migration` before Phase 3 |

All seven fixes are localized — no rewrite needed.
