# Plan: Auto-sync `~/.claude/MEMORY` from loom every 5 min

> **Status: implemented** in PR following branch `codex/loom-claude-memory-autosync`. Final approach: Option A as described below — script extracted to `lib/chezmoi-memory-sync.nix`, consumed by both the Darwin launchd agent (`hosts/mac-shared.nix`) and a new Linux systemd user timer (`users/joost/home-manager-server.nix`, gated to loom). Verified: eval shows the timer on loom and absent from j7. After `make switch NIXNAME=loom`, run `systemctl --user enable --now chezmoi-memory-sync.timer` to start it.

## Context

`hosts/mac-shared.nix` defines a `chezmoiMemorySync` shell script and wires it as a `launchd.user.agents.chezmoi-memory-sync` with `StartInterval = 300`. That's why frequent `chore(memory): auto-sync ...Z` commits show up on `javdl/dotfiles@main` — but **only from Darwin machines**. Loom (Linux) has no equivalent, so anything you write to `~/.claude/MEMORY` on loom stays local until you manually push (or another machine's auto-sync incidentally captures nothing relevant).

You want loom to participate in the same 5-minute cadence.

The existing script is solid:
- Re-adds only `~/.claude/MEMORY` to chezmoi source (scoped, won't touch other files).
- Bails out if nothing under `MEMORY/` changed.
- **Refuses** if the chezmoi working copy has changes outside `MEMORY/` — preserves manual chezmoi edits.
- Pulls remote + rebases before pushing to minimize "stale info" rejections.

So this is wiring, not rewriting.

## Options

### Option A — Move script to shared, wire systemd user timer on Linux (recommended)
Refactor: lift `chezmoiMemorySync` out of `hosts/mac-shared.nix` into `users/shared-home-manager.nix` (or a small new `modules/chezmoi-memory-sync.nix`). Reference it from launchd on Darwin (unchanged behavior) and from a new `systemd.user.timers.chezmoi-memory-sync` + matching `.service` on Linux.

**Pros:** declarative, version-controlled, runs even when no session is open (loom has `users.users.joost.linger = true` so user services run permanently — confirmed in `hosts/loom.nix` via `home-manager-server.nix` chain). Matches the existing `agent-mail` user-service pattern (`users/joost/home-manager-server.nix:618`). One source of truth for the script body.

**Cons:** small refactor (extracting the script + parameterizing for both init systems). Touches three files: `hosts/mac-shared.nix` (consume from new shared location), `users/shared-home-manager.nix` (or new module) for the script, `users/joost/home-manager-server.nix` for the Linux timer.

**Effort:** ~30 min including build verification.

### Option B — Inline systemd timer in `home-manager-server.nix`, leave Darwin alone
Don't refactor. Just add a new `systemd.user.timers.chezmoi-memory-sync` + service to `users/joost/home-manager-server.nix` that runs a Nix-package-built copy of the same script logic.

**Pros:** zero risk to Darwin path. Smallest diff.

**Cons:** duplicates the script body across two files (mac-shared.nix and home-manager-server.nix). When the script changes, two places to update. Drift risk.

**Effort:** ~15 min.

### Option C — User cron via home-manager `services.cron`
Add a `*/5 * * * *` cron entry calling the existing script.

**Pros:** simplest mental model.

**Cons:** cron is uncommon on NixOS; user systemd timers are the idiomatic alternative; harder to inspect (`systemctl --user list-timers` vs digging through cron logs).

**Effort:** ~10 min.

### Option D — Generic-NixOS module wrapping both init systems
`modules/chezmoi-memory-sync.nix` exposes `services.chezmoiMemorySync.enable` that automatically picks systemd vs launchd based on `pkgs.stdenv.isDarwin`. Imported per-host.

**Pros:** cleanest interface for adding more machines later. Maps onto the existing module pattern (`modules/repo-updater.nix`, `modules/nixos-auto-update.nix`).

**Cons:** more code than needed for the immediate goal. Reasonable later refactor; overkill for "make it work on loom now".

**Effort:** ~45–60 min.

## Recommendation

**Option A.** It's the minimum that doesn't duplicate the script body, and it lays the right foundation for adding the same job to other Linux hosts later (j7, fu137) by just enabling a flag in their home-manager files. Option D is the eventual destination, but Option A gets you 80% of the structural benefit at ~half the work.

## Detailed plan (Option A)

### Files modified

1. **`users/shared-home-manager.nix`** — append a derivation/script attribute:
   ```nix
   chezmoiMemorySync = pkgs.writeShellScript "chezmoi-memory-sync" ''
     <existing body from hosts/mac-shared.nix:7-43, unchanged>
   '';
   ```
   Export it via the attrs the shared module returns (or pass through `extraSpecialArgs` if needed). Verify by `nix eval` for both a Darwin and a Linux host.

2. **`hosts/mac-shared.nix`** — drop the local `chezmoiMemorySync` `let` binding and reference the shared one. The `launchd.user.agents.chezmoi-memory-sync` block stays put, just dereferences the shared script. No functional change on Darwin.

3. **`users/joost/home-manager-server.nix`** — add (right after the existing `agent-mail` service):
   ```nix
   # Auto-sync ~/.claude/MEMORY to chezmoi remote every 5 min on loom.
   # Mirror of the Darwin launchd agent in hosts/mac-shared.nix.
   # Guarded to loom for now — widen the condition or move to a module if
   # we want it on more Linux hosts.
   systemd.user.services.chezmoi-memory-sync = lib.mkIf (isLinux && currentSystemName == "loom") {
     Unit = {
       Description = "Auto-sync ~/.claude/MEMORY to chezmoi remote";
       After = [ "network-online.target" ];
       Wants = [ "network-online.target" ];
     };
     Service = {
       Type = "oneshot";
       ExecStart = "${shared.chezmoiMemorySync}";  # or whatever the shared accessor is
       # The script writes a log line to stdout/stderr; systemd journal captures it.
     };
   };

   systemd.user.timers.chezmoi-memory-sync = lib.mkIf (isLinux && currentSystemName == "loom") {
     Unit.Description = "Run chezmoi-memory-sync every 5 minutes";
     Timer = {
       OnBootSec = "2min";          # don't fight first-boot home-manager activation
       OnUnitActiveSec = "5min";    # match Darwin's StartInterval = 300
       AccuracySec = "30s";         # systemd default is 1 min — tighter for predictable cadence
       Persistent = false;          # don't catch-up after suspend; just resume rolling cadence
     };
     Install.WantedBy = [ "timers.target" ];
   };
   ```

### Why loom-only initially
The other server-shaped Linux hosts that share `home-manager-server.nix` (desmondroid, jacksonator, peterbot, rajbot, jeevanator, lennardroid, github-runner-*) belong to *other users* — they load their own per-user home-manager files. So this guard is mainly a style hedge; in practice the file isn't loaded on those machines. But explicit > implicit.

### Verification plan
1. `nix build --no-link --print-out-paths .#nixosConfigurations.loom.config.system.build.toplevel` — green.
2. After `make switch NIXNAME=loom`:
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now chezmoi-memory-sync.timer
   systemctl --user list-timers chezmoi-memory-sync.timer
   ```
3. Wait 5 min, then `journalctl --user -u chezmoi-memory-sync -n 30` — expect one of:
   - "Nothing under dot_claude/MEMORY/ changed, bailing" (most common, no-op runs)
   - "Pushed to remote" if MEMORY was modified
   - "skip: working copy has changes outside dot_claude/MEMORY/" if there are uncommitted manual chezmoi edits
4. Modify a file in `~/.claude/MEMORY/` manually, wait 5–6 min, then `jj log -r 'main@origin' --no-pager -n 3` in `~/.local/share/chezmoi` — expect a new `chore(memory): auto-sync ...Z` commit from the loom hostname.
5. Build a Darwin host (any) to confirm the refactor didn't regress the launchd path.

### Edge cases / things to keep in mind
- **Race with manual pushes.** The script already does `jj git fetch && jj rebase -d main` before pushing. Should handle the existing race fine, just makes the racy peer Linux instead of only Darwin.
- **Auth.** The script needs SSH credentials to push to `github.com/javdl/dotfiles`. Loom has SSH agent + GitHub access (we just pushed manually). Should work.
- **Secret-scanner false positives.** The existing script uses `chezmoi re-add --keep-going` to skip false positives. Keep that flag.
- **Network down.** Script doesn't fail loudly on network errors — `jj git fetch || true`. That's intentional and fine.
- **First-boot timing.** `OnBootSec = "2min"` delays the first run so it doesn't fight home-manager activation. Adjust if it gets in the way.

## Out of scope for this plan
- Widening the guard to all Linux hosts (j7, fu137, etc.). Easy follow-up once the loom one is proven.
- Promoting to Option D (full module). Worth doing once we have 3+ hosts running this.
- Adding metrics / Prometheus exporter for "minutes since last successful push". Premature.
