# Repo Improvement Backlog — 2026-07-28

Whole-repo audit of `javdl/nixos-config`. Every finding below was verified by running the
command shown, not inferred. Follow-up to `docs/nix-best-practices-improvements.md`
(2026-06-13), whose P1 items are now largely done — status deltas in **F1**.

Approve by ID (e.g. "do A1, A3, B1"). Batches are suggested groupings, not requirements.

---

## Batch A — CI is broken and the fleet auto-deploys anyway (P0)

### A1. `homeConfigurations."omarchy"` does not evaluate — one-line fix
- **Evidence:** `nix eval .#homeConfigurations."omarchy".activationPackage.drvPath` →
  `error: function 'anonymous lambda' called without required argument 'currentSystemName'`.
  `j9` and `githubrunner` both evaluate OK.
- **Cause:** `flake.nix:421+` imports `./users/joost/home-manager.nix` with `isWSL` and
  `inputs` but omits `currentSystemName`. The identical `j9` block at `flake.nix:384-389`
  passes `currentSystemName = "j9";`.
- **Impact:** This is the exact error failing CI's `inventory` job, which aborts the whole
  Determinate CI run before any build happens.
- **Action:** add `currentSystemName = "omarchy";` (or fold into B3).
- **Effort:** minutes.

### A2. `main` has been red for at least the last 3 pushes
- **Evidence:** `gh run list` — "Build 🏗️ and Cache ❄️" = **failure** on `d8ec672`,
  `d20712c`, and `89e738b` (5m44s–6m28s each). Job breakdown: `inventory` failure →
  `build` **skipped** → `success` failure.
- **Impact:** No build, no cache population, no signal. Red is the normal state, so a real
  regression would not stand out.
- **Action:** fix A1/A3/A5, then treat red main as blocking.
- **Effort:** follows from A1/A3/A5.

### A3. FlakeHub cache auth fails on every run (HTTP 401)
- **Evidence:** in every CI run — `FlakeHub: cache initialized failed: Unauthenticated:
  HTTP 401 Unauthorized` and `##[error]Unable to authenticate to FlakeHub. Individuals must
  register at FlakeHub.com; Organizations must create an organization at FlakeHub.com.`
- **Impact:** `flakehub-cache-action` is wired into 3 workflows but contributes nothing;
  every CI build starts cold. Wasted minutes on every push.
- **Action:** either register the account/org so the token works, or drop the cache action
  and rely on the Cachix path the repo already uses (`lib/cachix-push-hook.nix`).
- **Effort:** small, but needs your FlakeHub account decision.

### A4. Nothing gates host configs before 15 machines auto-deploy them
- **Evidence:** `checks` contains exactly one entry, `format` (`flake.nix:180-200`), and its
  own comment says lints are excluded. Meanwhile `grep -rl nixosAutoUpdate hosts/` → **15
  hosts**, each pulling `github:javdl/nixos-config#<host>` daily at 4 AM.
- **Impact:** a commit that evaluates on your laptop but breaks another host reaches the
  fleet unreviewed. A1 proves broken outputs can sit on `main` undetected.
- **Action:** add a `checks.<system>.eval-hosts` that evaluates
  `nixosConfigurations.*.config.system.build.toplevel.drvPath` for every x86_64-linux host
  (eval-only is cheap; full builds are not needed to catch this class of break).
- **Effort:** half a day incl. CI wiring.

### A5. Two host configs are genuinely broken — `vm-aarch64`, `vm-aarch64-utm`
**Upgraded from "CI enumerates a system it cannot build" after reproducing locally.**
- **Evidence:** swept all 22 NixOS configs with
  `nix eval .#nixosConfigurations.<h>.config.system.build.toplevel.drvPath` →
  **20 OK, 2 FAIL**, both with `error: Unsupported system: aarch64-linux`. Same error as
  the CI log, so this is not a runner problem — the configs do not evaluate anywhere.
- **Cause:** 13 tools in `lib/overlays.nix` publish no aarch64-linux binary and end their
  source selection with `or (throw "Unsupported system for <tool>: ...")` — grepai, bv, slb,
  csctf, brenner, toon, gws, br, ntm, dcg, caam, agent-browser, s2p. Any aarch64-linux host
  pulling the default package set aborts evaluation.
- **Note:** the same file already uses the non-fatal idiom for other tools
  (`xfSource = xfSources.${system} or null;`), and consumers guard it with
  `lib.optional (pkgs.xf != null)`. So the fix has an in-repo precedent.
- **Action — needs your call:**
  - **(a) Make the 13 throw sites `or null`** and guard each consumer. Consistent with the
    existing pattern, keeps both VMs. ~13 overlay edits plus consumer guards, and the
    tool-updater automation that regenerates `lib/overlays.nix` must be taught the same
    idiom or it will reintroduce the throws.
  - **(b) Retire `vm-aarch64` / `vm-aarch64-utm`** if the Apple-Silicon VMs are no longer
    used. Minutes, but it removes two hosts.
- **Status:** excluded from the new `checks.eval-hosts` gate via `knownBrokenHosts` in
  `flake.nix`, with the reasoning inline, so the break is tracked rather than silent.
- **Effort:** (a) 1–2 h, (b) minutes.

---

## Batch B — Duplication that is actively causing bugs (P1)

### B1. Five colleague profiles are ~99% identical
- **Evidence:** `users/{desmond,jackson,jeevan,peter,rajesh}/home-manager-server.nix` are
  **634 lines each**. `diff` against desmond: jackson **6** differing lines, jeevan **6**,
  rajesh **6**, peter 78. ~3,000 lines of copy-paste.
- **Impact:** every fleet-wide change is a 5-file edit that silently drifts.
- **Action:** apply the pattern that already exists in `users/agent-lib/home-manager.nix` —
  one parameterized module + five ~15-line stubs carrying name/email/GitHub user. Keep
  peter's 78-line delta explicit.
- **Effort:** 1 day, mechanical, verifiable by comparing evaluated configs before/after.

### B2. `users/shared-home-manager.nix` never reaches any server profile
- **Evidence:** `grep -rn "shared.sessionVariables" users/` → only
  `users/music/home-manager.nix:62` and `users/joost/home-manager.nix:340`. Every
  `*-server.nix` imports the file for `shared.ntmShellInit` but defines its own
  `home.sessionVariables` from scratch.
- **Impact:** a "shared" value silently applies to desktops only. Hit today: `_ZO_DOCTOR`
  had to be written twice (`89e738b`), and that comment now documents the trap.
- **Action:** have server profiles merge `shared.sessionVariables`, or split the shared file
  into clearly-named "desktop-only" vs "all-hosts" sections so the split is intentional.
- **Effort:** small; do it with B1.

### B3. `homeConfigurations."j9"` and `."omarchy"` are near-duplicates
- **Evidence:** `flake.nix:371-420` vs `421-459` — same pkgs import, same
  `extraSpecialArgs`, same module list; omarchy just forgets one argument (A1).
- **Action:** one helper taking the hostname; A1 disappears as a class of bug.
- **Effort:** small.

### B4. `lib/overlays.nix` is a 1,486-line generated monolith
- **Evidence:** `wc -l lib/overlays.nix` → 1486 (was 1474 at the June audit — still growing).
  It is excluded from `nix fmt` and from `checks.format` because the tool-updater rewrites it
  wholesale.
- **Action:** carried over from the June audit (2.2) — split to `overlays/<tool>.nix` with a
  thin aggregator, so per-tool bumps are small diffs and the generated-file exclusion shrinks.
- **Effort:** 1-2 days, background project.

### B5. ~25 near-identical config blocks in `flake.nix`
- Carried over from June audit 2.3, unchanged. `flake.nix` is 459 lines, most of it
  boilerplate that `genAttrs` over a host table would collapse.
- **Effort:** half a day. Do **after** A4 so the eval check protects the refactor.

### B6. `users/githubrunner/` vs `users/github-runner/`
- **Evidence:** both directories exist. The first serves `homeConfigurations."githubrunner"`
  (Ubuntu), the second the NixOS runner hosts.
- **Action:** rename one (June audit 3.1 suggested `users/ubuntu-runner`).
- **Effort:** minutes.

---

## Batch C — Repo weight: 27 MB of the 29 MB is not config (P2)

### C1. `mcp_agent_mail/` — 8.5 MB, 268 tracked files, referenced by nothing
- **Evidence:** `git ls-files mcp_agent_mail | wc -l` → 268; `du -sh` → 8.5M. The only Nix
  references are in `lib/overlays.nix:346-354`, and they fetch the **Rust rewrite**
  (`Dicklesworthstone/mcp_agent_mail_rust`) from GitHub releases. The vendored Python tree —
  including an 11,198-line `app.py`, a 648 KB `sql-wasm.wasm`, and its own `uv.lock` — is not
  built, imported, or packaged by this repo.
- **Action:** delete it (history keeps it), or move it to its own repo if still wanted.
- **Effort:** minutes. Confirm nothing external clones this path first.

### C2. Two large binaries dominate the tree
- **Evidence:** `users/joost/wallpapers/04167_unreachable_3840x2160.png` **15.8 MB**;
  `.github/images/screenshot.png` **3.3 MB**.
- **Action:** fetch the wallpaper via `fetchurl` in the overlay like any other asset, and
  compress/resize the README screenshot.
- **Effort:** small. Note: this shrinks checkouts, not `.git` history.

### C3. Root-level leftovers
- `nix.custom.conf.before-nix-darwin2` (660 B backup of a pre-migration config),
  `PROMPT_review.md` (1.1 KB), `claude.sh`, `omarchy-packages.sh`,
  `omarchy-packages-uninstall.sh`.
- **Action:** delete the backup, and move the scripts under `scripts/` if they are still used.
- **Effort:** minutes — but confirm each, per the AGENTS.md "audit siblings" rule.

### C4. `modules/programs.nix` is an all-comment dead file
- **Evidence:** 556 bytes, and `flake.nix:127-131` excludes it from both `nix fmt` and
  `checks.format` because it "is not valid standalone Nix".
- **Action:** delete it and drop both exclusions. Same question for
  `users/music/autostart.nix` ("truncated" per the same comment).
- **Effort:** minutes.

---

## Batch D — Lint debt (P2)

### D1. 200 deadnix findings, 0 statix findings
- **Evidence:** `deadnix hosts modules lib users flake.nix` → 200 unused declarations
  (mostly `Unused lambda pattern: pkgs`); `statix check` → clean.
- **Impact:** the flake comment says lints are kept out of `checks` "to avoid blocking on
  pre-existing legacy findings" — this quantifies that debt. statix is already clean, so it
  could be gated **today** at zero cost.
- **Action:** (a) add `statix` to `checks` now; (b) burn down deadnix in one mechanical pass,
  then gate it too.
- **Effort:** (a) minutes, (b) half a day.

### D2. 32 TODO/FIXME/XXX markers across `.nix` files
- **Action:** triage into real issues or delete. Low priority, but they hide real gaps
  (e.g. unfilled SSH keys / `hashedPassword` placeholders in colleague bootstrap docs).

---

## Batch E — Secrets and stale infrastructure (P1)

### E1. `.sops.yaml` still has no admin recipient
- **Evidence:** `.sops.yaml:15` — `# - &admin_joost age1...`, still commented out. Every
  creation rule encrypts to the host key alone.
- **Impact:** lose or reprovision a host and its secrets are unrecoverable — you can only
  recreate them. This was P2.4 in the June audit and is the oldest open risk in the repo.
- **Action:** add your age key, add it to every `key_groups`, `sops updatekeys secrets/*.yaml`.
- **Effort:** under an hour, high value.

### E2. Placeholder age key committed
- **Evidence:** `.sops.yaml` — `&hermes-fu age1__TBD__derived_after_provisioning__`.
- **Action:** derive the real key or remove the anchor and `secrets/hermes-fu.yaml` until the
  host exists.

### E3. Decommissioned hosts still wired in
- **Evidence:** `loom` appears in **16** tracked files including `flake.nix`, `.sops.yaml`,
  `secrets/loom.yaml`, `hosts/loom.nix`, `hosts/hardware/loom.nix` — AGENTS.md says it is
  passive and pending cancellation. `github-runner-06` still has a `.sops.yaml` anchor and a
  `flake.nix` entry though the box is now `bali`.
- **Action:** once you cancel loom at Hetzner, remove host + hardware + flake entry + sops
  anchor + secrets file in one commit. Same for the `github-runner-06` leftovers now.
- **Effort:** half a day, mostly waiting on your decommission decision.

---

## Batch F — Docs and process (P3)

### F1. The June audit's completed items are not marked done
- Verified now as **done**: `nix.yml` deleted (1.1), `formatter` added (1.2),
  `checks.format` added (1.3), `devShells` + `.envrc use flake` added (2.1).
- Still open: 2.2 → **B4**, 2.3 → **B5**, 2.4 → **E1**, 3.1 → **B6/B3**, 3.3 (global
  `allowUnfree`).
- **Action:** annotate the doc with status so it stays trustworthy, or fold it into this file.

### F2. `NIXNAME ?= vm-intel` remains a silent footgun
- **Evidence:** `Makefile:10`. AGENTS.md warns about it in prose ("always pass NIXNAME
  explicitly"), which means it has already bitten someone.
- **Action:** make the switch/test targets fail fast when `NIXNAME` is unset instead of
  defaulting to a VM. Documentation is not a guardrail.
- **Effort:** minutes.

### F3. `docs/security-audit-2026-03-06.md` has no follow-up tracking
- Nearly five months old with no recorded status. Either re-run it or record which findings
  were accepted/fixed.

---

## Suggested order

1. **A1** (minutes) → unblocks CI immediately.
2. **A3, A5** → get CI green and actually caching.
3. **A4** → the gate that makes the daily 4 AM fleet auto-update safe.
4. **E1** → oldest unmitigated risk; cheap.
5. **C1, C3, C4** → free weight loss, no behaviour change.
6. **B1 + B2** → the duplication that keeps generating bugs.
7. **D1(a)** statix gate, then **B5, B4** behind the A4 safety net.
