# Nix Best-Practices Audit & Improvement Plan

**Date:** 2026-06-13
**Scope:** Whole-repo audit of `javdl/nixos-config` against Nix best practices.
**Primary reference:** [Best practices for Nix at work — Determinate Systems](https://determinate.systems/blog/best-practices-for-nix-at-work/), supplemented with general flake/CI/formatting conventions.

This is an analysis + backlog, not a set of applied changes. Items are grouped by priority and each has a concrete action and the evidence behind it.

---

## TL;DR

The flake is in good shape on the things that matter most: it pins `nixpkgs`, uses `inputs.X.follows` to dedupe, avoids `flake-utils`/`flake-parts` (per DS advice), keeps secrets out of the store via `sops-nix`, and already runs FlakeHub Cache + automated lock updates. The biggest gaps are **tooling hygiene**, not architecture:

1. The plain `nix.yml` CI job is **dead** (triggers on `master`, default branch is `main`) and uses a deprecated runner.
2. There is **no formatter** (`nix fmt`), **no `checks`**, and **no `devShells`** output — three things the DS article and the wider ecosystem treat as table stakes.
3. `lib/overlays.nix` is a **1,474-line monolith** of hand-pinned binary hashes — a maintenance hotspot.
4. `flake.nix` has **~25 near-identical `darwinConfigurations` blocks** that beg for a data-driven helper.

---

## What the repo already does well (keep doing)

| Practice (DS article) | Status | Evidence |
|---|---|---|
| Pin primary `nixpkgs` | ✅ | `nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05"` (`flake.nix:13`) |
| Update inputs frequently | ✅ | `lock-updater.yml` (cron Mon/Fri) + `flake-checker.yml` (daily) |
| Avoid flake helper libraries | ✅ | Hand-rolled `lib/mksystem.nix`; no `flake-utils`/`flake-parts` |
| Keep secrets out of the Nix store | ✅ | `sops-nix` wired in `mksystem.nix:71`; only encrypted YAML is committed |
| Least access / private cache | ✅ (partial) | Uses `DeterminateSystems/flakehub-cache-action` |
| Dedupe transitive nixpkgs | ✅ | `inputs.*.follows = "nixpkgs"` on wsl, snapd, home-manager, darwin, disko, sops-nix, hermes-agent, nix-index-database |
| `result` not committed | ✅ | Present as symlink but `.gitignore:2` ignores it |

---

## Priority 1 — Fix / high impact, low effort

### 1.1 `nix.yml` never runs (wrong branch) and uses a dead runner
- **Evidence:** `.github/workflows/nix.yml` triggers on `push: branches: [master]`, but the default branch is `main` (`git symbolic-ref` → `main`). The push trigger therefore never fires. It also pins `runs-on: ubuntu-20.04` (retired GitHub runner image) and `cachix/install-nix-action@v31` with a commented-out, never-filled `# TODO: add a binary cache`.
- **Why it matters:** A CI job that looks green but never executes is worse than no job — it creates false confidence. The `fh.yml` (Determinate CI) job already builds + caches on `main`/PRs, so `nix.yml` is largely redundant.
- **Action (pick one):**
  - **Delete `nix.yml`** and rely on `fh.yml` (`DeterminateSystems/ci`) which already does `nix flake check` + builds with caching, **or**
  - Fix it: change `master` → `main`, bump to `ubuntu-24.04`, and wire the `cachix` cache it references (or remove the dead TODO).
- **Recommendation:** delete it; `fh.yml` supersedes it.

### 1.2 No formatter (`nix fmt`)
- **Evidence:** No `formatter` output in `flake.nix` (grep returns nothing); no `treefmt.toml`/`.nixfmt`/`nixfmt` config anywhere. `.editorconfig` enforces 2-space indent but nothing enforces Nix-specific formatting.
- **Why it matters:** A monorepo with 80+ `.nix` files and multiple contributors (colleague servers, agents committing) drifts in style without a canonical formatter. `AGENTS.md` even documents a 2-space/camelCase style — but it's unenforced.
- **Action:** Add a `formatter` output. Minimal, no new inputs:
  ```nix
  # in outputs, alongside the configs
  formatter = nixpkgs.lib.genAttrs
    [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ]
    (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
  ```
  Then `nix fmt` works and can be gated in CI (see 2.1). `nixfmt-rfc-style` is the official-track formatter.

### 1.3 `nix flake check` does almost nothing
- **Evidence:** `flake.nix` exposes only `nixosConfigurations`, `darwinConfigurations`, `homeConfigurations` (confirmed via `nix flake show`). There is no `checks` output, so `nix flake check` only type-checks the flake skeleton and evaluates configs — it doesn't lint, format-check, or smoke-build anything.
- **Why it matters:** The single most valuable CI signal for a config repo is "does every host still evaluate/build." Right now that's implicit and partial.
- **Action:** Add a `checks` output that at minimum runs a format check and (optionally) `statix`/`deadnix`. Example skeleton:
  ```nix
  checks.${system} = {
    format = pkgs.runCommand "fmt-check" {} ''
      ${pkgs.nixfmt-rfc-style}/bin/nixfmt --check ${./.}/**/*.nix && touch $out'';
    # lint = pkgs.runCommand "statix" {} "${pkgs.statix}/bin/statix check ${./.} && touch $out";
  };
  ```

---

## Priority 2 — Medium impact

### 2.1 Add a `devShell` (DS "adopt Nix gradually, dev shells first")
- **Evidence:** No `devShells` output; `.envrc` is just `export PATH="$HOME/.local/bin:$PATH"` — it does **not** `use flake`.
- **Why it matters:** The DS article's #1 adoption recommendation is dev environments. Contributors to *this* repo currently have no pinned toolchain (`nixfmt`, `sops`, `ssh-to-age`, `statix`, `deadnix`, `nixos-anywhere`) — they must install ad hoc. A `devShell` + `direnv` makes the contributor toolchain reproducible.
- **Action:**
  ```nix
  devShells.${system}.default = pkgs.mkShell {
    packages = with pkgs; [ nixfmt-rfc-style statix deadnix sops ssh-to-age age ];
  };
  ```
  and change `.envrc` to `use flake` (keeping the PATH export).

### 2.2 `lib/overlays.nix` is a 1,474-line hand-pinned binary monolith
- **Evidence:** `wc -l lib/overlays.nix` → 1474. It contains per-tool blocks (`grepai`, `bv`, `cass`, …) each with 4 hard-coded `sha256` hashes per platform.
- **Why it matters:** This is the repo's biggest maintenance hotspot and exactly the kind of "many independently-versioned components in one place" the DS article warns about (SemVer / split-flakes advice). Every tool bump is a manual hash dance.
- **Actions (incremental, not a rewrite):**
  - Split into `overlays/<tool>.nix` files (one per tool) imported by a small `lib/overlays.nix` aggregator — smaller diffs, clearer ownership. There is already an `update-overlays` skill; per-file structure makes it more reliable.
  - Where a tool publishes proper releases, prefer `fetchFromGitHub` + `buildGoModule`/`buildRustPackage` over raw-binary `fetchurl`, so updates only need a rev + one hash (matches the AGENTS.md preference order, just applied more widely).
  - Longer term, the DS "split into multiple flakes" idea maps here: these CLI tools could live in a sibling `tools` flake consumed as an input, versioned independently of the OS configs.

### 2.3 `flake.nix` host list is ~25 copy-pasted blocks
- **Evidence:** `darwinConfigurations.{fu129,fu146,j8,macbook-pro-m1,…}` are byte-for-byte identical except the name; many `nixosConfigurations` differ only by `user`/`server`.
- **Why it matters:** Boilerplate this repetitive invites drift and merge noise (and the file already carries dead entries — see 3.1). A data table is the idiomatic fix.
- **Action:** Drive the common cases from a list:
  ```nix
  darwinHosts = [ "fu129" "fu146" "j8" "macbook-pro-m1" "macbook-air-m1" /* … */ ];
  darwinConfigurations = nixpkgs.lib.genAttrs darwinHosts
    (name: mkSystem name { system = "aarch64-darwin"; user = "joost"; darwin = true; });
  ```
  Keep the hand-written blocks only for the genuinely special hosts (raphael/pstate/server/hmConfig overrides).

### 2.4 `.sops.yaml` has no admin recipient — only host keys
- **Evidence:** `keys:` lists only per-host age keys; the `&admin_joost` line is commented out, and every `creation_rule` encrypts to the host key alone (the `# - *admin_joost  # Uncomment after adding admin key` notes confirm this is known).
- **Why it matters:** Secrets are encrypted **only** to the target host. If a host is lost/reprovisioned, you cannot decrypt or rotate its secrets from your workstation — you can only re-create them. This is a recoverability risk, not a leak risk.
- **Action:** Add your personal age key as `&admin_joost`, add it to every `key_groups`, and `sops updatekeys secrets/*.yaml`. This is the "least access" principle done right: host keys for runtime, one admin key for recovery.

---

## Priority 3 — Cleanup / hygiene

### 3.1 Stale / duplicate files
- **`hosts/hardware/vm-aarch64-prl.nix`** still exists though `flake.nix:88` documents its config was removed. → delete the orphan hardware file.
- **`users/githubrunner/` vs `users/github-runner/`** — two near-homonym user dirs (one for the Ubuntu `homeConfigurations."githubrunner"`, one for the NixOS runner hosts). This is a footgun. → rename one (e.g. `users/githubrunner` → `users/ubuntu-runner`) and update the `homeConfigurations` reference.
- **`homeConfigurations."omarchy"` and `."j9"`** are ~90% duplicate. → factor the shared module into one helper, parameterize the hostname.

### 3.2 Double nixpkgs instantiation in overlays
- **Evidence:** `lib/overlays.nix` does `import inputs.nixpkgs-unstable { … config.allowUnfree = true; }` inside the overlay, producing a second full pkgs evaluation per system.
- **Why it matters:** Minor eval-time/memory cost; also means unstable packages don't inherit the rest of your nixpkgs config. Acceptable, but worth a comment explaining the intent, or hoisting the unstable import so it's instantiated once and shared.

### 3.3 `allowUnfree = true` is global
- **Evidence:** `mksystem.nix:56` sets it for every system. Fine for a personal fleet, but it's a blanket allow. → consider `allowUnfreePredicate` listing the specific unfree packages you actually use, so a new unfree dep is a conscious choice rather than silent.

### 3.4 CI consistency
- The three Determinate workflows (`fh.yml`, `flake-checker.yml`, `lock-updater.yml`) are coherent and modern. Once `nix.yml` is removed (1.1), the CI story is clean. Consider adding the format/lint check (1.3/2.1) as a step in `fh.yml` so style is enforced on PRs.

---

## Not recommended (considered and rejected)

- **Splitting the OS configs into many flakes now.** The DS article recommends this for *teams shipping versioned artifacts*. For a single-owner fleet config, one flake with `mkSystem` is the right call and already avoids the helper-library bloat the article warns about. The only split worth doing is pulling the CLI-tool overlays out (2.2), and even that is optional.
- **Adding `nixConfig` binary-cache settings to the flake.** The flake header (`flake.nix:4-7`) already explains this is set daemon-side to avoid "not a trusted user" warnings on macOS. Leave it.

---

## Suggested order of execution

1. Delete `nix.yml` (1.1) — 2 min, removes false signal.
2. Add `formatter` + `devShell` + `.envrc use flake` (1.2, 2.1) — unlocks `nix fmt` and a real contributor shell.
3. Add a `checks.format` (1.3) and wire it into `fh.yml`.
4. Run `nix fmt` once across the tree (expect a large but mechanical diff).
5. Tackle `flake.nix` host-table refactor (2.3) and `.sops.yaml` admin key (2.4).
6. Background project: split `lib/overlays.nix` per-tool (2.2) + stale-file cleanup (3.1).
