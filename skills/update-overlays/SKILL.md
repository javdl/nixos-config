---
name: update-overlays
description: >
  Bump third-party packages in lib/overlays.nix (codex, the Dicklesworthstone
  Rust CLIs, grepai, gemini-cli, agent-browser, gws, ...) to their latest
  upstream version, refresh sha256 hashes for every platform, and validate
  with `make test NIXNAME=loom`. Use when the user says "update overlays",
  "update overlay packages", "bump codex", "update <pkg> to latest", "refresh
  tool versions", "update dicklesworthstone tools", "update all the AI tools",
  or "check for new versions of our git tools". Skip ubs, cm, cco — those are
  build-from-source and must be bumped manually.
---

# Update Overlays

Bump third-party overlay packages in `lib/overlays.nix` to their latest upstream releases.

## When to use

Triggered by phrases like:
- "update overlays" / "update overlay packages"
- "update <pkg> to latest" (e.g. "update codex", "update bv", "bump gemini-cli")
- "refresh tool versions" / "update the AI tools"
- "update dicklesworthstone tools"
- "check for new versions of our git tools"

## In-scope packages

All packages defined in `/home/joost/nixos-config/lib/overlays.nix` that follow the standard `<name>Version` + `<name>Sources` pattern (one `<name>Version` string and a per-platform attrset of `{url, sha256/hash}`).

| Name | Source | Repo / npm pkg |
|---|---|---|
| grepai | gh-release | yoanbernabeu/grepai |
| bv (beads-viewer) | gh-release | Dicklesworthstone/beads_viewer |
| cass | gh-release | Dicklesworthstone/coding_agent_session_search |
| slb | gh-release | Dicklesworthstone/slb |
| csctf | gh-release | Dicklesworthstone/chat_shared_conversation_to_file |
| brenner | gh-release | Dicklesworthstone/brenner_bot |
| toon | gh-release | Dicklesworthstone/toon_rust |
| ms | gh-release | Dicklesworthstone/meta_skill |
| gws | gh-release | googleworkspace/cli |
| br (beads_rust) | gh-release | Dicklesworthstone/beads_rust |
| ntm | gh-release | Dicklesworthstone/ntm |
| dcg | gh-release | Dicklesworthstone/destructive_command_guard |
| caam | gh-release | Dicklesworthstone/coding_agent_account_manager |
| agent-browser | gh-release | vercel-labs/agent-browser |
| pi | gh-release | Dicklesworthstone/pi_agent_rust |
| xf | gh-release | Dicklesworthstone/xf |
| mcp-agent-mail | gh-release | Dicklesworthstone/mcp_agent_mail_rust |
| fsfs (frankensearch) | gh-release | Dicklesworthstone/frankensearch |
| casr | gh-release | Dicklesworthstone/cross_agent_session_resumer |
| s2p | gh-release (bare binary) | Dicklesworthstone/source_to_prompt_tui |
| pt | gh-release | Dicklesworthstone/process_triage |
| rch | gh-release | Dicklesworthstone/remote_compilation_helper |
| ru | gh-release (bare binary) | Dicklesworthstone/repo_updater |
| codex | npm | @openai/codex |
| gemini-cli | gh-release (JS bundle) | google-gemini/gemini-cli |

## Out of scope — refuse with message

`ubs`, `cm`, `cco` build from source and have multi-hash structures (per-file module hashes, cargoHash). If asked to bump any of these, reply:

> "<pkg> is build-from-source and must be bumped manually. See `lib/overlays.nix` for its hash structure."

Do not edit anything for these packages.

## Workflow

### 1. Parse target list

- No package names mentioned → update all in-scope packages.
- Package names mentioned (e.g. "update codex and bv") → update only those.
- Any out-of-scope name → refuse with the message above and skip it.

### 2. For each target, discover latest version

**npm** (codex only):
```bash
curl -s https://registry.npmjs.org/@openai/codex/latest | jq -r .version
```

**gh-release** (everything else):
```bash
curl -s "https://api.github.com/repos/<owner>/<repo>/releases/latest" | jq -r .tag_name | sed 's/^v//'
```

If the request rate-limits (HTTP 403 from api.github.com), retry once with `gh release view --repo <owner>/<repo> --json tagName -q .tagName | sed 's/^v//'` (gh is in PATH on this machine).

Read the current `<name>Version = "...";` from `lib/overlays.nix`. If it matches the latest, mark as **up to date** and skip.

### 3. Fetch new hashes

For each platform key in the package's `<name>Sources` attrset, substitute the new version into the existing URL template (just replace the version number in the URL string — every other part of the URL is unchanged).

For each new URL:

1. **Verify it exists:**
   ```bash
   code=$(curl -sIL -o /dev/null -w "%{http_code}" "$url")
   ```
   If non-200, abort this package's bump and report `URL HTTP <code> — skipped`. Do not delete the package's block.

2. **Detect the hash format** in the *current* file for that entry:
   - Starts with `sha256-` and ends with `=` → **SRI**
   - 64 hex chars (`[0-9a-f]{64}`) → **hex**
   - Otherwise (e.g. `0kk6lxc...`) → **legacy base32**

3. **Compute new hash in that same format:**
   ```bash
   raw=$(nix-prefetch-url --type sha256 "$url")                       # legacy base32 (nix32)
   sri=$(nix hash convert --hash-algo sha256 --to sri    "sha256:$raw")
   hex=$(nix hash convert --hash-algo sha256 --to base16 "sha256:$raw")
   ```
   `nix hash convert` uses `--to <format>` with a space (the format names are `sri`, `base16`, `nix32`, `base64`). Do **not** write `--to-sri` or `--to-base16` — those are not valid flags on Nix 2.33+ and the command silently fails with an empty hash. Pick the variant matching the current format.

   - codex uses SRI `hash = "sha256-...";`
   - Most packages use legacy base32 `sha256 = "0xxx...";`
   - slb uses hex `sha256 = "9cee...";`

   **Preserve the exact existing format** — both the variable name (`sha256` vs `hash`) and the encoding. Goal: minimal diff.

### 4. Edit `lib/overlays.nix`

Use the `Edit` tool. For each package:

- One edit for `<name>Version = "OLD";` → `<name>Version = "NEW";`
- One edit per platform replacing the old hash string with the new one.

Use exact-string replacements (the `old_string` parameter of `Edit`) — never `replace_all` (hashes can collide in theory; play it safe).

Tip: when matching `<name>Version`, include enough surrounding context so the match is unique (e.g. the comment line above it). Same for hashes — include the URL line above each `sha256 = "...";` to disambiguate.

### 5. Validate

After **all** target packages are edited, run a single validation:

```bash
make test NIXNAME=loom
```

This builds `nixosConfigurations.loom` which pulls every overlay package on x86_64-linux. It will not exercise darwin/aarch64 builds, but those use the same fetchurl pattern — if the URL is valid and the hash matches what `nix-prefetch-url` returned, the build will succeed.

If `make test` fails:
- Surface the error to the user.
- Identify which package's block contains the build failure (usually the error mentions a `/nix/store/.../codex-0.130.0.drv` or similar path).
- **Do not auto-revert** — let the user inspect and decide.

### 6. Report

Print a Markdown table summarising every package the user asked about:

```
| package        | old     | new     | status        |
|----------------|---------|---------|---------------|
| codex          | 0.114.0 | 0.130.0 | built ok      |
| grepai         | 0.35.0  | 0.36.0  | built ok      |
| bv             | 0.15.2  | 0.15.2  | up to date    |
| xf             | 0.2.0   | 0.3.0   | URL 404 (linux-arm64) — skipped |
| ubs            | —       | —       | manual only   |
```

End with: "Working tree is dirty — review the diff and commit when ready." **Do not commit.**

## Hash format quick reference

For `lib/overlays.nix`, three formats are in use. Detect and preserve:

| Format       | Looks like                                     | Convert command                                              |
|--------------|------------------------------------------------|--------------------------------------------------------------|
| SRI          | `sha256-keEqVsSccCyGxcQoEc+j1RW21rwZbXC6...=`  | `nix hash convert --hash-algo sha256 --to sri    sha256:$raw` |
| hex          | `9ceed8af0ec18b425bafda9bb6b289e1e42faec...`   | `nix hash convert --hash-algo sha256 --to base16 sha256:$raw` |
| legacy base32| `0kk6lxc904j3mxxjxp7df4hq9swib8rj5srqsqayk...` | use `$raw` from `nix-prefetch-url` directly                   |

`$raw` = the stdout of `nix-prefetch-url --type sha256 <url>` (base32 SRI-unprefixed).

## Inline-version edge case (`ru`, `gemini-cli`)

Two in-scope packages **do not** have a `<name>Version = "...";` variable — the version is hardcoded directly inside the URL string and the derivation's `version = "...";` field:

- `ru` (Dicklesworthstone/repo_updater, `lib/overlays.nix` ~line 886) — `releases/download/v1.2.1/ru` is literal.
- `gemini-cli` (google-gemini/gemini-cli, ~line 1438) — `releases/download/v0.32.1/gemini.js` is literal.

For these two, replace the version string everywhere it appears in the package's block (typically: once in the URL, once in `version = "...";`, sometimes once more in `homepage` if pinned). Use multiple targeted `Edit` calls — don't try to do this with `replace_all` on the whole file because the version digits may collide with other packages.

## URL templating gotchas

Some packages use distinct URL shapes across platforms — re-use the *existing* URL string verbatim and only substitute the version number. Examples already in the file:

- `grepai`: `grepai_${version}_linux_amd64.tar.gz`
- `cass`: `cass-linux-amd64.tar.gz` (no version in filename)
- `csctf`: `csctf-linux-x64` (bare binary, no .tar)
- `codex`: `codex-${version}-linux-x64.tgz` (npm registry)
- `ubs` modules: `https://raw.githubusercontent.com/.../v${version}/modules/<file>` (out of scope, but noted)

If upstream changes the asset naming between releases, the URL check in step 3.1 will fail and the package is skipped. Tell the user the asset name appears to have changed and let them update manually.

## Examples

**User:** "update codex to latest"
→ Fetch npm latest, compare to current `codexVersion`, refresh 4 SRI hashes, edit, run `make test NIXNAME=loom`, report.

**User:** "update overlays"
→ Walk every in-scope package above, refresh anything stale, single `make test` at the end.

**User:** "update ubs"
→ Refuse: "ubs is build-from-source and must be bumped manually."

**User:** "bump dicklesworthstone tools"
→ Filter the in-scope table to repos with owner `Dicklesworthstone`, update those.

## Notes

- The skill never touches `flake.lock`. That's `make update`'s job.
- The skill never commits or pushes — leave the diff for the user to review.
- All hash math runs on the local machine. No network calls except `curl` to GitHub/npm and the `nix-prefetch-url` download.
