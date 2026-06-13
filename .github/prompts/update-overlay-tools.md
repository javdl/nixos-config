Update the pinned versions of the pre-built third-party tools in `lib/overlays.nix`
to their latest upstream releases, recomputing every hash. Work autonomously; do not
ask questions.

## What is pinned

`lib/overlays.nix` packages ~25 CLI tools (codex, beads_rust/`br`, ntm, dcg, caam,
cass, ubs, gemini-cli, agent-browser, etc.). Each tool has:

- a `<name>Version = "x.y.z";` Nix variable, and
- a per-platform source set with a `url` and a `sha256` (nix base32 **or** hex) or a
  `hash` (SRI `sha256-...`) field.

A few are special: `ubs` fetches a main script plus ~10 module + ~13 helper files
each with its own hash; `cass-memory` builds from source via `fetchFromGitHub` + a
fixed-output `bunDeps` derivation (`outputHash`); `cco` is pinned to a git commit
(leave it unless there is an obvious newer tagged release — never guess a commit).

## Procedure

For each `*Version` variable:

1. Find the latest release. GitHub: `gh api repos/<owner>/<repo>/releases/latest --jq .tag_name`.
   npm (codex): `curl -s https://registry.npmjs.org/@openai/codex/latest | jq -r .version`.
   The owner/repo is visible in each tool's `url`.
2. If the latest equals the current pin, skip the tool.
3. If newer, bump the version variable and recompute **every** platform hash:
   - `nix-prefetch-url <url>` gives a nix base32 hash (no `--unpack` for plain
     fetchurl of a tarball/binary; use `--unpack` for `fetchzip`/`fetchFromGitHub`).
   - Convert to the format that entry already uses:
     `nix hash convert --hash-algo sha256 --to base16 <b32>` for hex,
     `nix hash convert --hash-algo sha256 --to sri <b32>` for SRI.
4. **Asset names and archive layouts change between releases.** If a download 404s or
   a build fails, inspect the real release assets
   (`gh api repos/<owner>/<repo>/releases/tags/<tag> --jq '.assets[].name'`) and the
   tarball contents (`tar tzf` / `tar tJf`). Update the `url` pattern, archive
   extension, `unpackPhase`, `sourceRoot`, install path, and the `meta.platforms`
   list as needed. If a platform's asset disappears upstream, remove that platform
   entry; if a new platform appears, you may add it.
5. For `cass-memory`: bump `rev`, recompute the `fetchFromGitHub` `hash`
   (`nix-prefetch-url --unpack https://github.com/<owner>/<repo>/archive/<tag>.tar.gz`,
   then `--to sri`), then set the `bunDeps` `outputHash` to
   `sha256-AAAA...AAA=` (44-char zero placeholder), build it via
   `nix build .#nixosConfigurations.<somehost>.pkgs.cass-memory --no-link`, and paste
   the "got:" hash from the mismatch error.

## Validate

- Run `nix fmt lib/overlays.nix` (the repo enforces nixfmt via a CI check).
- `nix-instantiate --parse lib/overlays.nix` must succeed.
- For each x86_64-linux tool you changed, confirm it builds:
  `nix build .#nixosConfigurations.<host>.pkgs.<attr> --no-link` (pick a Linux host
  from `flake.nix` `nixosConfigurations`; the overlay attr name is the Nix attribute,
  e.g. `beads-rust`, `destructive-command-guard`, not the binary name). A hash
  mismatch means you used the wrong hash; a builder failure usually means the archive
  layout changed (see step 4).

## Output

Only edit files in the working tree — **do not** run `git commit`, `git push`, or open
a PR yourself; the workflow does that. End by printing a concise markdown summary
table of `tool | old version | new version` for everything you bumped (and note any
tool you intentionally skipped because an asset/layout change needs human review).
