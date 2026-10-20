# Nix Performance Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce flake evaluation time, input/cache overhead, memory waste, and garbage-collection contention without changing any host's intended package or service closure.

**Architecture:** Keep the current single-flake and `mkSystem` design. Expose host evaluation as independent checks so Determinate Nix can schedule them concurrently, memoize the unstable package set once per platform, and make cache/GC ownership explicit. Pilot Determinate Nix only on Bali, the dedicated `nixos-config` evaluation runner, while retaining upstream Nix on the rest of the Linux fleet.

**Tech Stack:** Nix flakes, NixOS/nix-darwin modules, Determinate Nix, Bash policy checks, GitHub Actions.

---

## Design

The evaluation path will retain explicit coverage of every NixOS, nix-darwin, and standalone Home Manager configuration. Instead of concatenating all derivation paths into one `eval-hosts` value, `flake.nix` will generate one `checks.x86_64-linux.eval-<kind>-<name>` derivation per configuration. `nix flake check --all-systems --no-build` can then discover those attributes independently; CI separately builds native checks.

`lib/overlays.nix` will build a lazy `pkgsUnstableForSystem` map outside the overlay callback. Every host of the same platform will share the same imported unstable package set. The packages selected from unstable remain unchanged and derivation paths must match the baseline.

Cache policy will retain the official Nix cache implicitly and the personal Cachix cache globally. Devenv and nix-community caches are added only for non-server profiles that consume those artifacts. The unused Hyprland input and cache, unused `fh` input, duplicate official cache, and obsolete 512 MiB download buffer are removed together. `nixos-hardware` follows the primary nixpkgs input.

Nix GC will have one owner per machine. Linux `automaticNixGC` owns generation/store GC, while `diskCleanup` owns logs, temporary files, and containers. Determinate Nixd owns GC on Macs and on the Bali pilot. Obsolete `keep-outputs` and redundant `keep-derivations` overrides are removed fleet-wide.

## Task 1: Establish policy tests and baselines

**Files:**
- Create: `tests/nix-performance-policy.sh`

1. Add structural assertions for every performance policy in this plan.
2. Run `bash tests/nix-performance-policy.sh`.
3. Confirm it fails on the current aggregate evaluation gate and obsolete settings.
4. Record the hash of all NixOS toplevel derivation paths with evaluation caching disabled.

## Task 2: Parallelize explicit host evaluation

**Files:**
- Modify: `flake.nix`
- Modify: `.github/workflows/flake-checker.yml`

1. Replace the aggregate `eval-hosts` derivation with `mkHostEvalChecks`, producing one check per host/configuration.
2. Run CI evaluation with `--all-systems --no-build` and build native checks separately.
3. Retain a lazy-tree-disabled retry only when the normal evaluation fails.

## Task 3: Share unstable nixpkgs and prune inputs

**Files:**
- Modify: `lib/overlays.nix`
- Modify: `flake.nix`
- Modify: `flake.lock`

1. Hoist unstable imports into a lazy system-indexed map.
2. Remove the unused `fh` and Hyprland inputs.
3. Make `nixos-hardware` follow the primary nixpkgs input.
4. Add the official Determinate input without making it follow nixpkgs, preserving its binary-cache hits.
5. Update the lock file and inspect the resulting toplevel changes against the intentional Nix, cache, and retention policy changes.

## Task 4: Scope caches and remove obsolete download tuning

**Files:**
- Modify: `lib/mksystem.nix`
- Modify: `modules/cachix.nix`
- Modify: `hosts/mac-shared.nix`

1. Pass `isServer` to modules.
2. Keep the personal cache globally and add Devenv/nix-community only for desktop profiles.
3. Remove the duplicate official cache, Hyprland cache, and 512 MiB download buffer.
4. Evaluate one server and one desktop consumer to verify their effective substituter lists.

## Task 5: Consolidate store retention and garbage collection

**Files:**
- Modify: `hosts/*.nix` and `modules/agent-dev-box.nix`
- Modify: `modules/disk-cleanup.nix`
- Delete: `modules/darwin-nix-gc.nix`

1. Remove `keep-outputs` and redundant `keep-derivations` overrides.
2. Remove Nix GC from `diskCleanup` and schedule it away from 04:00 auto-updates.
3. Remove the custom Darwin GC module and its two consumers.
4. Evaluate representative Linux and Darwin configurations.

## Task 6: Pilot Determinate Nix on Bali

**Files:**
- Modify: `hosts/bali.nix`

1. Import `inputs.determinate.nixosModules.default`.
2. Remove Bali's upstream `nix.package`, extra options, and custom `automaticNixGC`; Determinate Nixd becomes the GC owner.
3. Evaluate Bali's Nix package/version, services, cache settings, and system toplevel.

## Task 7: Verification and delivery

1. Run `bash tests/nix-performance-policy.sh` and confirm it passes.
2. Run representative `nix eval` consumer checks.
3. Run `nix flake check --all-systems --no-build --print-build-logs`.
4. Build native flake checks.
5. Repeat evaluation benchmarks and compare them with the baseline.
6. Rebase on `origin/main`, rerun the full verification, commit, and push.

## Measured results

- Clean-tree evaluation of every NixOS toplevel with the eval cache disabled improved from 88.08 seconds to 84.68 seconds (3.9%).
- The lock graph shrank from 46 nodes to 36 even after adding the Determinate Nix pilot input.
- `nix flake check --all-systems --no-build` exposes each explicit host check independently and completed successfully.
- Bali evaluates with `determinate-nix-3.22.2`, a `determinate-nixd` socket, no custom GC service, and `keep-outputs = false`.
- Server configurations retain only the personal cache plus NixOS's official default; desktop configurations retain Devenv and nix-community as consumers require.
