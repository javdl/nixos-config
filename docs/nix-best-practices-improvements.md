# Nix.dev Best-Practices Audit

**Date:** 2026-08-30

**Scope:** Active and tracked Nix code in `javdl/nixos-config`

**Primary reference:** [nix.dev: Best practices](https://nix.dev/guides/best-practices.html)

**Status:** The actionable findings from this audit were implemented on 2026-08-30.

## Summary

The repository now follows all seven practices covered by the referenced nix.dev page.
The flake pins every external input, active Nixpkgs imports make their configuration and
overlay policy explicit, and the repository contains no lookup-path dependencies, unsafe
nested attribute updates, or working-directory-derived source names.

| Practice | Status | Repository evidence |
|---|---|---|
| Quote URLs | Pass | Nix URL values are strings; apparent unquoted matches occur only inside comments or multiline strings. |
| Avoid `rec` | Pass | No `rec { ... }` remains in tracked Nix code. |
| Avoid file-level `with` | Pass | The former `with lib;` in `modules/github-actions-runner.nix` was replaced with explicit imports. Scoped `with pkgs;` package lists remain where provenance is local and clear. |
| Avoid lookup paths | Pass | No executable `<nixpkgs>` or other `$NIX_PATH` lookup is used. Flake inputs are explicit and locked. |
| Reproducible Nixpkgs configuration | Pass | Direct Nixpkgs imports set `config` and `overlays`; the unstable overlay import explicitly uses `overlays = [ ];`. |
| Safe attribute-set updates | Pass | Every `//` use was inspected; all are flat additions or intentional whole-record overrides, not accidental nested updates. |
| Reproducible source paths | Pass | No derivation uses a local `src = ./.` or equivalent; package sources are fixed-output fetches. |

## Changes made from the audit

### CI guardrail

`.github/workflows/flake-checker.yml` now runs for pull requests, pushes to `main`, its
daily schedule, and manual dispatches. It has two distinct responsibilities:

- The GitHub-hosted job validates both `nixpkgs` inputs and fails on provenance,
  supported-ref, and lockfile-policy violations. Input freshness remains the responsibility
  of the existing twice-weekly lock-updater workflow.
- The dedicated `nixos-config` runner executes `nix flake check --print-build-logs`, which
  evaluates every NixOS, nix-darwin, and standalone Home Manager configuration and runs
  the flake checks.

Because this repository is public, fork pull requests never execute arbitrary code on the
persistent self-hosted runner. Full checks run for trusted same-repository pull requests,
pushes to `main`, scheduled runs, and manual runs.

### Nix language cleanup

- Removed four unnecessary `rec` argument sets from `flake.nix`.
- Removed the unnecessary recursive result set from `lib/mksystem.nix`.
- Moved the repo-updater version into an outer `let` and removed its recursive derivation.
- Replaced the file-level `with lib;` in `modules/github-actions-runner.nix` with explicit
  `inherit (lib)` bindings.
- Made the unstable Nixpkgs overlay policy explicit with `overlays = [ ];`.
- Removed the unused second unstable Nixpkgs import from `users/joost/home-manager.nix`.

### Whole-tree hygiene

Three tracked but unreferenced files prevented parser-backed tools from treating the full
tree as valid Nix and were removed:

- `modules/programs.nix` — an all-comment abandoned module.
- `users/music/autostart.nix` — a truncated expression with no consumer.
- `hosts/ubuntu/fu137.nix` — an obsolete standalone shell importing missing sibling paths;
  `fu137` is now managed by the flake's Omarchy Home Manager configuration.

Their formatter exclusions were removed. A full `statix` parse now reports zero syntax
errors across tracked Nix files.

## Verification

The implementation is accepted only when all of these commands succeed:

```bash
nix flake check --print-build-logs
nix eval .#nixosConfigurations.github-runner-03.config.services.github-actions-runner.packages.forRunner --apply builtins.length
nix eval --raw .#nixosConfigurations.loom.config.services.repoUpdater.package.version
nix eval --raw .#nixosConfigurations.loom.pkgs.gh.version
```

The representative consumer evaluations protect the shared runner module, repo-updater
derivation, and unstable package overlay in addition to the whole-flake evaluation.

## Separate style-debt backlog

`statix check .` currently reports 204 non-syntax suggestions:

| Code | Finding | Count |
|---|---|---:|
| 20 | Repeated dotted keys in attribute sets | 117 |
| 4 | Assignment instead of `inherit` from another set | 72 |
| 3 | Assignment instead of `inherit` | 7 |
| 8 | Unnecessary parentheses | 4 |
| 2 | Useless `let ... in` expression | 2 |
| 10 | Empty function argument pattern | 2 |

These findings are not violations of the seven practices audited above. They should be
reduced in small, evaluation-protected batches rather than with a whole-repository
automatic rewrite. `lib/overlays.nix` remains outside the format gate because the package
update workflow edits its large mechanical blocks in place; changing that policy belongs
with the planned overlay split and updater-skill migration.
