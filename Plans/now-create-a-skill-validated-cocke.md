# Plan: `update-overlays` skill

## Context

Every few weeks the third-party tools we vendor in `lib/overlays.nix` (codex, the Dicklesworthstone Rust CLIs, grepai, gemini-cli, gws, agent-browser, vercel-labs/agent-browser, etc.) release new versions. Right now bumping one of them is a manual ritual: read the overlay block, look up the latest version on GitHub or npm, `nix-prefetch-url` for each platform, edit the version + N hashes in `lib/overlays.nix`, then `make test` to validate. That's exactly what we just did for codex 0.114.0 → 0.130.0.

We have ~25 overlay packages with the same shape (one `<name>Version` string + a `<name>Sources` attrset of per-platform `{url, sha256}`), so the work is mechanical and well-suited to a skill.

This skill automates that exact flow for the "easy" packages (single-version + per-platform hash pattern), validates with `make test NIXNAME=loom`, and reports a diff for the user to commit. The fragile build-from-source packages (`ubs`, `cm`, `cco`, `ironclaw`) are out of scope.

## Skill location

```
/home/joost/nixos-config/skills/update-overlays/SKILL.md
```

The existing `skills/workos` is a symlink into `~/.agents/skills/workos`. To make this skill discoverable system-wide, the user can add a reverse symlink later:
```
ln -s /home/joost/nixos-config/skills/update-overlays ~/.agents/skills/update-overlays
```
Creating that symlink is **not** part of the skill — the plan only adds the in-repo file. The user can wire up discovery themselves.

## Package catalog (in scope)

Source: `/home/joost/nixos-config/lib/overlays.nix`. All use the `<name>Version` + `<name>Sources` pattern, one fetchurl per platform.

| Package | Line | Source | Repo / npm pkg | Platforms |
|---|---|---|---|---|
| grepai | 20–40 | gh-release | yoanbernabeu/grepai | 4 |
| bv (beads-viewer) | 42–62 | gh-release | Dicklesworthstone/beads_viewer | 4 |
| cass | 64–80 | gh-release | Dicklesworthstone/coding_agent_session_search | 3 |
| slb | 83–102 | gh-release | Dicklesworthstone/slb | 4 |
| csctf | 104–124 | gh-release | Dicklesworthstone/chat_shared_conversation_to_file | 4 |
| brenner | 126–146 | gh-release | Dicklesworthstone/brenner_bot | 4 |
| toon | 148–168 | gh-release | Dicklesworthstone/toon_rust | 4 |
| ms | 170–182 | gh-release | Dicklesworthstone/meta_skill | 2 |
| gws | 184–208 | gh-release | googleworkspace/cli | 4 |
| br (beads_rust) | 210–230 | gh-release | Dicklesworthstone/beads_rust | 4 |
| ntm | 232–252 | gh-release | Dicklesworthstone/ntm | 4 |
| dcg | 254–274 | gh-release | Dicklesworthstone/destructive_command_guard | 4 |
| caam | 276–296 | gh-release | Dicklesworthstone/coding_agent_account_manager | 4 |
| agent-browser | 298–318 | gh-release | vercel-labs/agent-browser | 4 |
| pi | 320–332 | gh-release | Dicklesworthstone/pi_agent_rust | 2 |
| xf | 334–350 | gh-release | Dicklesworthstone/xf | 3 |
| mcp-agent-mail | 352–364 | gh-release | Dicklesworthstone/mcp_agent_mail_rust | 2 |
| fsfs (frankensearch) | 366–378 | gh-release | Dicklesworthstone/frankensearch | 2 |
| casr | 380–392 | gh-release | Dicklesworthstone/cross_agent_session_resumer | 2 |
| s2p | 394–414 | gh-release (bare binary) | Dicklesworthstone/source_to_prompt_tui | 4 |
| pt | 416–424 | gh-release | Dicklesworthstone/process_triage | 1 |
| rch | 426–434 | gh-release | Dicklesworthstone/remote_compilation_helper | 1 |
| ru | ~886 | gh-release (bare binary) | Dicklesworthstone/repo_updater | varies |
| codex | 1382–1436 | npm | @openai/codex | 4 |
| gemini-cli | 1438–1465 | gh-release (JS bundle) | google-gemini/gemini-cli | 1 |

**Out of scope (build-from-source / multi-file):** `ubs` (~90 module-file hashes per version), `cm` (cargoHash), `cco`, `ironclaw` (vendorHash). The skill should refuse these with a clear message: "build-from-source packages must be bumped manually."

## How the skill works

The skill is prose + commands the agent runs, modeled on `~/.agents/skills/deploy-servers/SKILL.md`. No new scripts/binaries — it instructs Claude to:

### 1. Parse a target list
- No args → update all in-scope packages.
- Args = space-separated package names (`codex grepai bv`) → update only those.
- Reject any name in the out-of-scope list with the manual-bump message.

### 2. For each target, discover latest version
- **npm** (codex only): `curl -s https://registry.npmjs.org/@openai/codex/latest | jq -r .version`
- **gh-release** (everything else): `curl -s https://api.github.com/repos/<owner>/<repo>/releases/latest | jq -r .tag_name` then strip leading `v` if present.

Compare against the current `<name>Version` string in `lib/overlays.nix`. If equal, skip and report "up to date". Otherwise continue.

### 3. Compute new hashes
For each platform entry in the package's `<name>Sources` attrset:
1. Substitute the new version into the existing URL template.
2. `curl -sIL -o /dev/null -w "%{http_code}" "$url"` — abort the package's update if any URL returns non-200 (upstream may have changed the asset naming).
3. Fetch the hash:
   - **SRI format** (codex, e.g. `sha256-...=`): `nix-prefetch-url --type sha256 "$url"` then `nix hash convert --hash-algo sha256 --to-sri sha256:<raw>`.
   - **Legacy base32** (most packages, e.g. `0kk6lxc...`): `nix-prefetch-url --type sha256 "$url"` and use the raw output.
   - **Hex** (e.g. slb `9ceed8af...`): `nix-prefetch-url --type sha256 "$url"` then `nix hash convert --hash-algo sha256 --to-base16 sha256:<raw>`.

   Detect the current format by inspecting the existing hash string in the file (starts with `sha256-` → SRI; 64 hex chars → hex; else legacy base32). Preserve format → minimal diff.

### 4. Edit `lib/overlays.nix`
Use the `Edit` tool to change:
- `<name>Version = "OLD";` → `<name>Version = "NEW";`
- Each platform's `sha256 = "OLD";` (or `hash = "OLD";` for codex) → new value.

One block per package, exact-string replacements so diffs are minimal.

### 5. Validate
- `make test NIXNAME=loom` once at the end (after all bumps) — single build covers every changed package because they're all in one overlay.
- If `make test` fails, report which package(s) were just bumped and surface the build error. Do not auto-revert.

### 6. Report
Print a table:
```
package        old      → new      status
codex          0.114.0  → 0.130.0  built ok
grepai         0.35.0   → 0.36.0   built ok
bv             0.15.2   → 0.15.2   up to date
xf             0.2.0    → 0.3.0    URL 404 — skipped
```
Leave the working tree dirty. Do **not** commit (per user choice).

## Critical files

- **New:** `/home/joost/nixos-config/skills/update-overlays/SKILL.md` — the skill itself, ~150–200 lines of frontmatter + prose modeled on `deploy-servers/SKILL.md`.
- **Read-only reference (in-skill):** `lib/overlays.nix` — the skill instructs Claude to grep/read this for the target package's block.
- **Validation command:** `make test NIXNAME=loom` — from this repo's `Makefile`.

## Frontmatter shape

```yaml
---
name: update-overlays
description: >
  Bump third-party packages in lib/overlays.nix (codex, the Dicklesworthstone
  Rust CLIs, grepai, gemini-cli, agent-browser, gws, …) to their latest
  upstream version, refresh sha256 hashes for every platform, and validate
  with `make test NIXNAME=loom`. Use when the user says "update overlays",
  "bump codex", "update <pkg> to latest", "refresh tool versions", "update
  dicklesworthstone tools", or "update all the AI tools". Skip ubs, cm, cco,
  ironclaw — those are build-from-source and must be bumped manually.
---
```

## Existing patterns reused

- **Skill format / frontmatter / inventory table style:** `~/.agents/skills/deploy-servers/SKILL.md` is the model.
- **Per-platform `<name>Sources` attrset:** used by every in-scope package in `lib/overlays.nix` (lines 20–434, plus codex 1382–1436). The skill leans on this consistency — same shape means one editing recipe works for all.
- **Hash prefetch + format conversion:** `nix-prefetch-url` + `nix hash convert` (built-in to nix 2.x, no extra deps). This is the same approach used manually for the codex bump.
- **Validation:** `make test NIXNAME=loom` — already the documented test command in `CLAUDE.md`. No new tooling.

## Verification (after creating the skill file)

1. **File exists and parses:** `cat /home/joost/nixos-config/skills/update-overlays/SKILL.md | head -20` — confirm YAML frontmatter renders cleanly.
2. **Discoverable (optional):** if the user adds `ln -s /home/joost/nixos-config/skills/update-overlays ~/.agents/skills/update-overlays`, the skill should appear in the available-skills list on next Claude Code session start.
3. **Smoke test (manual, after approval):** run the skill against a known-stale package. We just bumped `codex` so it's now current — pick another like `gemini-cli` or `bv` and ask the skill to bump it. Expect: latest version detected, hash fetched, file edited, `make test NIXNAME=loom` green, a one-row report.
4. **Failure mode test:** ask the skill to bump `ubs` — expect refusal with the manual-bump message and no file changes.
5. **No-op test:** re-run the skill on a just-bumped package — expect "up to date" status, zero file edits.

Once the skill works on a single package, the broader workflow (`update-overlays` with no args → walk the whole list) is just iteration, no extra logic.
