# Fleet rollout: `omp` + `hermes` coding agents

**Coordinator:** bali (Herdr command center)
**Branch under test:** `worktree-add-coding-agents` @ `755f159`, one commit ahead of `main`
**Status:** packets drafted, none dispatched

## Objective (inferred — confirm)

`755f159` adds `omp` (oh-my-pi, pinned 18.0.11) and `hermes` (hermes-agent flake input,
`minimal` variant) to the five home-manager profiles that carry AI agent tooling. The commit
message records author-side verification (`nix flake check --no-build`, an x86_64-linux build of
both packages, one buildEnv collision check on `desmondroid`, one aarch64-darwin eval on `fu146`).

What has **not** happened is per-node verification on the Herdr fleet: no fleet machine has been
switched, and no node has been observed resolving `omp`/`hermes` on its real PATH. That is the
objective these packets cover.

## Coordinator findings before dispatch

Three things surfaced from reading the tree that change the shape of the work. They are stated
here because they are the coordinator's job to raise, not any single worker's.

**F1 — `exe` cannot receive this change as written.** `exedev@fu-herdr-dev` is not Nix-managed.
It is provisioned by `scripts/bootstrap-herdr-exe-node.sh`, which installs exactly one binary
(`herdr` 0.8.2, sha-pinned) into `~/.local/bin`, writes a config and a user unit, and runs
`herdr integration install claude` / `codex`. No Nix, no home-manager, no overlay. The commit's
"all machines" therefore means "all five home-manager profiles", which is a different set from
"all five fleet nodes". Packet P5 is a decision packet, not a rollout packet.

**F2 — `AGENTS.md` now overstates coverage.** The commit adds `omp`/`hermes` (and `pi`,
`opencode`, `grok`) to the table under "All dev servers include the following AI agent tooling."
The `fu-herdr-dev` worker is documented as fleet infrastructure in
`docs/herdr-command-center.md` but will not have them. Whatever P5 decides, the wording needs to
match reality.

**F3 — the runners' deploy path runs through `main`.** r03/r04/r05 auto-update daily at 04:00
from `github:javdl/nixos-config#<host>`. Nothing on the branch reaches them until it lands on
`main`. Workers can force the issue with a manual `nixos-rebuild switch` against a local checkout
of the branch, which is the recommended sequence: verify on one runner from the branch, then
merge, then let the other two take it via auto-update or manual switch.

Node → profile mapping, verified against `flake.nix` and `users/herdr-fleet.nix`:

| Packet | Node | Target | System | Profile consumed | Managed by |
|---|---|---|---|---|---|
| P1 | r03 | `joost@100.126.150.43` | x86_64-linux NixOS | `users/joost/home-manager-server.nix` | NixOS `#github-runner-03` |
| P2 | r04 | `joost@100.97.77.46` | x86_64-linux NixOS | `users/joost/home-manager-server.nix` | NixOS `#github-runner-04` |
| P3 | r05 | `joost@100.108.96.124` | x86_64-linux NixOS | `users/joost/home-manager-server.nix` | NixOS `#github-runner-05` |
| P4 | gpu | `joost@fu137` | x86_64-linux Arch | `users/joost/home-manager.nix` (`isOmarchy = true`) | standalone HM `#fu137` |
| P5 | exe | `exedev@fu-herdr-dev` | x86_64-linux (exe.dev) | none | `scripts/bootstrap-herdr-exe-node.sh` |

---

## P1 — r03: first-mover rollout and collision check

- **Owner:** r03 · **Branch:** `worktree-add-coding-agents` · **Depends on:** nothing · **Status:** ready
- **Why first:** r03 is `alwaysControl` in the fleet inventory and shares a profile with r04/r05.
  If the profile is wrong, it is wrong here, and P2/P3 should not burn a switch on it.

**Scope.** Build and switch `#github-runner-03` from the branch; prove both new binaries resolve;
prove nothing else regressed.

**Recon (before switching).** Record the pre-state so the delta is attributable:
`command -v omp hermes pi opencode grok || true`, `readlink -f "$(command -v herdr)"`, and free
disk on the store (`df -h /nix`).

**Apply.** Clone the branch to the box and
`sudo nixos-rebuild switch --flake "/path/to/checkout#github-runner-03"`. Do not point at
`github:javdl/nixos-config#github-runner-03` for this packet — that resolves to `main`, which does
not carry the commit.

**Expected evidence** (paste actual output, not a summary):
1. `omp --version` → `18.0.11`
2. `hermes --version` → `Hermes Agent v0.19.0`
3. `readlink -f "$(command -v omp)"` → a `/nix/store/...` path, and `file` on it showing a
   dynamically-linked ELF whose interpreter is patched into the store (the `autoPatchelfHook`
   claim in the commit message, confirmed at runtime rather than at build time)
4. `pi`, `opencode`, `grok` still resolve and still report their prior versions
5. `ntm deps -v` — full output; no new red
6. `HERDR_SESSION=agents herdr status server --json` healthy *after* the switch, and
   `herdr workspace list` unchanged. A switch that restarts the agent session is a regression
   worth reporting even though it is not caused by these two packages.
7. Wall-clock of the switch and the `hermes-agent` build specifically. It is a source build from a
   flake input, not a `fetchurl` binary; if it is not in a cache this is the expensive part of the
   whole rollout and every other node pays it too.

**Risks to watch.** buildEnv collisions in the joost server profile (only `desmondroid`'s
colleague profile was checked author-side); `/nix` disk pressure on a box that also holds GitHub
Actions runner work.

---

## P2 — r04: profile replication

- **Owner:** r04 · **Branch:** `worktree-add-coding-agents` · **Depends on:** P1 evidence items 1–5 · **Status:** blocked on P1

Same profile as P1, so this packet is about *replication*, not discovery. Same apply step, same
evidence list. The one thing P2 adds: `hermes --version` and `omp --version` must match P1
**exactly**. A mismatch means overlay or `flake.lock` drift between checkouts and is a stop-the-line
finding, not a footnote.

Additionally report whether `hermes-agent` came from cache or rebuilt (compare wall-clock against
P1's number).

---

## P3 — r05: profile replication + auto-update path

- **Owner:** r05 · **Branch:** `worktree-add-coding-agents` · **Depends on:** P1 evidence items 1–5 · **Status:** blocked on P1

Same as P2, plus one extra job nobody else can do: r05 is the node to prove the **production**
deploy path rather than the manual one. After the branch lands on `main`, run
`sudo nixos-rebuild switch --flake "github:javdl/nixos-config#github-runner-05"` and confirm it
produces the same closure as the manual branch switch. That is the path the 04:00 timer will take
on every colleague and runner box, and it is currently unverified for this change.

If the merge has not happened when this packet is picked up, do the manual switch first and leave
the `main`-path check open.

---

## P4 — gpu (fu137): Omarchy profile and PATH ownership

- **Owner:** gpu · **Branch:** `worktree-add-coding-agents` · **Depends on:** nothing (different profile — run in parallel with P1) · **Status:** ready

**Scope.** `fu137` on Arch consumes `users/joost/home-manager.nix` with `isOmarchy = true` through
`homeConfigurations."fu137"`. The `omp`/`hermes` additions sit in the shared package list at
`users/joost/home-manager.nix:247`, not behind an `isOmarchy` guard, so they should land — but this
is the only node where Nix packages share a PATH with a pacman-managed desktop, and it has never
been evaluated with these two present.

**Apply.** `home-manager switch --flake "/path/to/checkout#fu137"`.

**Expected evidence:**
1. `omp --version` → `18.0.11`; `hermes --version` → `Hermes Agent v0.19.0`
2. `command -v omp hermes` resolving into the **Nix profile**, not `/usr/bin`. Report the full
   `readlink -f` for each.
3. `pacman -Qo` on whatever those paths shadow, if anything, plus a grep of
   `/usr/share/omarchy/install/omarchy-base.packages` and `omarchy-other.packages` for `omp`,
   `oh-my-posh`, and `hermes`. CLAUDE.md is explicit that Omarchy owns its own package set; a
   silent shadow of a Quattro binary is exactly the class of breakage that rule exists to prevent.
4. No new files written under the protected paths (`~/.config/omarchy`, `~/.config/hypr`,
   terminal configs).
5. `ntm deps -v` and the `agents` Herdr session healthy after the switch.

**Risk.** `gpu` is the one fleet node with `alwaysControl = false`. If the switch disturbs the
session, recovery is more manual here than on the runners.

---

## P5 — exe: decision packet, not a rollout

- **Owner:** exe · **Branch:** none yet · **Depends on:** nothing to investigate; blocks the F2 doc fix · **Status:** ready

**Scope.** Do **not** try to switch this box; there is nothing to switch. Produce the evidence and
the options so the fleet can decide whether `fu-herdr-dev` is in or out of the coding-agent set.

**Evidence to gather:**
1. `ssh fu-herdr-dev 'command -v omp hermes pi opencode grok || echo absent'` — establish the
   current gap concretely
2. `ldd --version`, `uname -m`, `df -h $HOME` — the `omp` Linux release assets are dynamically
   linked against glibc, so a glibc-version answer decides whether the release binary is even
   usable outside Nix
3. Whether `~/.local/bin` is genuinely the only install surface, and whether the box has Nix

**Options to price (recommendation, not implementation):**
- **(a) Extend the bootstrap script.** Add sha256-pinned `omp` and `hermes` downloads to
  `scripts/bootstrap-herdr-exe-node.sh` alongside the existing `herdr` pin. Cheapest, matches the
  file's existing idiom, but forks version pinning away from `lib/overlays.nix` — two places to
  bump, which will drift.
- **(b) Install Nix + a standalone home-manager profile.** Single source of truth with the rest of
  the fleet, at the cost of putting Nix on an ephemeral exe.dev VM copied from `fu-dev-golden`.
- **(c) Declare exe out of scope** and correct the `AGENTS.md` wording so it claims coverage only
  where coverage exists.

State a recommendation with reasoning. Note that `hermes` under (a) is awkward: it has no release
binary at all — it is a flake-input source build — so (a) can realistically deliver `omp` but not
`hermes` without more work. That asymmetry should drive the recommendation.

---

## Cross-cutting checks the coordinator will reconcile

- **Version agreement.** `omp` and `hermes` versions must be identical across P1–P4. Any
  divergence is `flake.lock` drift and outranks every other finding.
- **`hermes-agent` build cost.** Four x86_64-linux nodes each build or fetch the `minimal` variant.
  If P1–P4 all report long source builds, the `minimal`-over-`full` choice was right but a binary
  cache is the real fix, and that is a follow-up.
- **Herdr session survival.** Every packet checks the `agents` session after its switch. A pattern
  across nodes means the switch path itself is disruptive.
- **Doc accuracy.** `AGENTS.md` gets one correction at the end, informed by P5.

## Synthesis protocol

Each worker returns: packet ID, status (`pass` / `pass-with-findings` / `fail` / `blocked`), the
raw command output for each numbered evidence item, and anything it chose not to run with a reason.
Absent output is treated as not-run, never as pass.

The coordinator flags disagreement when: two nodes on the same profile report different versions or
different resolved store paths; a node passes an item another node fails; or a worker's conclusion
is not supported by the output it pasted.
