# Plan: Simplify build-from-source overlays (ubs, cm)

> **Status:** queued — do after committing/pushing the current codex bump + `update-overlays` skill.

## Context

While building the `update-overlays` skill (see `Plans/now-create-a-skill-validated-cocke.md`), we marked four packages as out-of-scope because they build from source with multi-hash structures: `ubs`, `cm`, `cco`, `ironclaw`. Re-checking upstream as of 2026-05-12 showed that **two of them now publish proper GitHub releases** that would let us drop the build-from-source plumbing and bring them into the skill's scope.

This plan captures both cleanups so they can be done independently of the skill landing.

## Findings (2026-05-12)

| Package | Currently | Upstream now | Switch? |
|---|---|---|---|
| **ubs** | v5.0.6, fetches ~90 module files from `raw.githubusercontent.com/.../v5.0.6/modules/*` | **v5.2.75** ships a single self-contained `ubs` bash script (125 KB) as a release asset | Yes — easy win |
| **cm** (cass-memory) | v0.2.3, builds from source with `bun` + a fixed-output `bunDeps` derivation. Linux-only. Comment says "Pre-built GitHub release binaries are broken" | **v0.2.9** publishes per-platform binaries: `cass-memory-linux-x64` (144 MB), `cass-memory-macos-arm64` (106 MB), `cass-memory-macos-x64` (111 MB) — sizes consistent with embedded JS, suggesting the old breakage is fixed | Yes — needs a smoke test first |
| `cco` (nikvdp/cco) | build-from-source | No releases | No, stay as-is |
| `ironclaw` (nearai/ironclaw) | build-from-source v0.18.0 | v0.28.1 has full per-platform release tarballs | Out of scope for this plan (not Dicklesworthstone), but worth a separate task |

## Task 1 — ubs: switch to single-binary release

**Current block:** `lib/overlays.nix` lines ~499–590 (the `ubs` definition with the `ubsModules` attrset and the module-stitching `installPhase`).

**Replace with** a standard gh-release pattern (one `ubsVersion`, one `ubsSources` attrset). The asset is a single bash script named `ubs` that works on all platforms, so the four platform keys can all point at the same URL:

```nix
ubsVersion = "5.2.75";
ubsSources = {
  "x86_64-linux" = {
    url = "https://github.com/Dicklesworthstone/ultimate_bug_scanner/releases/download/v${ubsVersion}/ubs";
    sha256 = "<prefetch>";
  };
  "aarch64-linux"  = { /* same URL, same sha256 */ };
  "x86_64-darwin"  = { /* same URL, same sha256 */ };
  "aarch64-darwin" = { /* same URL, same sha256 */ };
};
```

Derivation shape (matches `csctf` at lines 104–124, which is also a bare-binary release):

```nix
ubs = prev.stdenv.mkDerivation {
  pname = "ubs";
  version = ubsVersion;
  src = prev.fetchurl { url = ubsSource.url; sha256 = ubsSource.sha256; };
  dontUnpack = true;
  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/ubs
    chmod +x $out/bin/ubs
  '';
  meta = with prev.lib; {
    description = "Ultimate Bug Scanner — pre-commit static analysis for AI coding workflows";
    homepage = "https://github.com/Dicklesworthstone/ultimate_bug_scanner";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };
};
```

**Hash:** one `nix-prefetch-url` call for the single asset URL, since the binary is identical across platforms.

**Steps:**
1. Confirm asset is genuinely platform-independent: `curl -sL .../v5.2.75/ubs | head -1` should be `#!/usr/bin/env bash` (already verified).
2. Prefetch: `nix-prefetch-url --type sha256 https://github.com/Dicklesworthstone/ultimate_bug_scanner/releases/download/v5.2.75/ubs` → use in legacy base32 format to match neighbouring packages.
3. Replace `lib/overlays.nix:499–590` with the simplified block above.
4. Remove the `ubsBaseUrl` / `ubsModules` plumbing entirely.
5. `make test NIXNAME=loom` to validate.
6. Verify the binary works: `result/bin/ubs --version` (or whatever flag prints version).
7. Update `skills/update-overlays/SKILL.md`:
   - Remove `ubs` from the out-of-scope refusal list.
   - Add `ubs` to the in-scope table.

**Expected diff:** drops ~90 lines, adds ~25.

## Task 2 — cm (cass-memory): test prebuilt binaries, switch if they work

**Current block:** `lib/overlays.nix` lines ~954–1007 (the `cass-memory` `mkDerivation` with `bunDeps` and on-build `bun build src/cm.ts --compile`).

**Problem to verify first:** the existing comment says

> "Pre-built GitHub release binaries are broken (bun cross-compilation doesn't embed scripts)."

That comment is from v0.2.3. v0.2.9 binaries are 100–160 MB, which is consistent with a fully-embedded bun bundle (bun's standalone compile produces a single fat binary). The old breakage may have been fixed.

**Smoke-test the prebuilt before refactoring:**
```bash
mkdir -p /tmp/cm-test && cd /tmp/cm-test
curl -sL https://github.com/Dicklesworthstone/cass_memory_system/releases/download/v0.2.9/cass-memory-linux-x64 -o cm
chmod +x cm
./cm --help          # or ./cm version
./cm <some command>  # exercise an actual memory op
```

If it runs and produces sane output, switch the overlay. If not, leave as-is and bump the existing from-source build to v0.2.9 (update the `rev`, `hash`, and `bunDeps.outputHash`).

**Switch-path replacement** (assuming binaries work):

```nix
cassMemoryVersion = "0.2.9";
cassMemorySources = {
  "x86_64-linux" = {
    url = "https://github.com/Dicklesworthstone/cass_memory_system/releases/download/v${cassMemoryVersion}/cass-memory-linux-x64";
    sha256 = "<prefetch>";
  };
  "x86_64-darwin" = {
    url = "https://github.com/Dicklesworthstone/cass_memory_system/releases/download/v${cassMemoryVersion}/cass-memory-macos-x64";
    sha256 = "<prefetch>";
  };
  "aarch64-darwin" = {
    url = "https://github.com/Dicklesworthstone/cass_memory_system/releases/download/v${cassMemoryVersion}/cass-memory-macos-arm64";
    sha256 = "<prefetch>";
  };
  # no aarch64-linux asset upstream
};
```

Derivation: bare binary, same shape as the `csctf` / proposed `ubs` block. Critically — **keep `dontStrip = true; dontPatchELF = true;`** because bun standalone binaries embed JS after the ELF section and Nix's default strip/patchelf will destroy it (the current code already does this).

**Steps:**
1. Run the smoke test above. **If it fails, abort this task** — just bump the existing from-source build to v0.2.9 instead (update `rev` and refetch `hash` + `bunDeps.outputHash`).
2. If smoke test passes:
   a. Prefetch hashes for the three platform binaries.
   b. Replace lines ~954–1007 with the simplified block.
   c. Drop the `bunDeps` derivation and its fixed-output hash.
   d. Expand `platforms` in `meta` to include the two macOS systems.
3. `make test NIXNAME=loom`.
4. Verify binary works as before: `result/bin/cm <command>`.
5. Update `skills/update-overlays/SKILL.md`:
   - Remove `cm` from the out-of-scope refusal list.
   - Add `cm` to the in-scope table.

**Expected diff:** drops ~30 lines of `bunDeps` plumbing, adds platform support for macOS, lifts the Linux-only restriction.

## Critical files

- **Modified:** `/home/joost/nixos-config/lib/overlays.nix` (ubs block ~499–590, cm block ~954–1007)
- **Modified:** `/home/joost/nixos-config/skills/update-overlays/SKILL.md` — update out-of-scope and in-scope tables

## Verification (both tasks combined)

1. `make test NIXNAME=loom` — green build with both packages on the new pattern.
2. `nix build --no-link --print-out-paths .#nixosConfigurations.loom.config.system.build.toplevel` then locate `ubs` and `cm` in `/nix/store/*`, run `--version` / `--help` on each — should produce real output, not a corrupted bun binary error.
3. Re-run the `update-overlays` skill (no args) — `ubs` and `cm` should now appear in its in-scope table and either say "up to date" or get bumped if newer releases exist.

## Out of this plan

- `cco` (nikvdp/cco) — no upstream releases. Stay build-from-source.
- `ironclaw` (nearai/ironclaw) — has releases (v0.28.1) but not Dicklesworthstone. Track separately if we want to simplify it.
