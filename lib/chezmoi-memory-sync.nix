# Shared chezmoi-memory-sync script. Re-adds ~/.claude/MEMORY into the chezmoi
# source repo, then commits + pushes via git if anything under MEMORY changed.
#
# Consumed by:
#   - hosts/mac-shared.nix    -> launchd.user.agents.chezmoi-memory-sync (Darwin)
#   - users/joost/home-manager-server.nix -> systemd.user.{service,timer}.chezmoi-memory-sync (loom)
#
# Both schedule it every 5 minutes. Body is identical across platforms.
pkgs:
pkgs.writeShellScript "chezmoi-memory-sync" ''
  set -u

  # systemd user services start with a minimal PATH that lacks chezmoi/git/grep.
  # Set PATH explicitly so the script works under both systemd (loom) and
  # launchd (Darwin) without needing per-consumer wrapping. These paths are
  # present on both NixOS and nix-darwin.
  export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"

  CHEZMOI_SRC="$HOME/.local/share/chezmoi"
  MEMORY_LIVE="$HOME/.claude/MEMORY"
  MEMORY_SRC_PATH="dot_claude/MEMORY"

  [ -d "$CHEZMOI_SRC" ] || { echo "no chezmoi source"; exit 0; }
  [ -d "$MEMORY_LIVE" ] || { echo "no live MEMORY"; exit 0; }

  # Re-add only the MEMORY tree. --keep-going skips secret-scanner false
  # positives (e.g. session titles containing "Api Key").
  chezmoi re-add --keep-going "$MEMORY_LIVE" || true

  cd "$CHEZMOI_SRC" || exit 0

  # Fail loudly if the source is not a git repo, or git is unavailable. Every
  # check below reads as "nothing to do" when git errors, so without this the
  # script exits 0 and the scheduler reports success every 5 minutes while
  # nothing is ever synced. That rot went unnoticed on bali for weeks.
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: $CHEZMOI_SRC is not a git repo, or git is unavailable" >&2
    exit 1
  fi

  # Only ever auto-commit on main. A detached HEAD or a feature branch means
  # someone is mid-operation; leave their state alone.
  branch="$(git symbolic-ref --short -q HEAD || true)"
  if [ "$branch" != "main" ]; then
    echo "skip: on branch '$branch', expected main" >&2
    exit 0
  fi

  # Bail out if nothing changed under MEMORY.
  if [ -z "$(git status --porcelain -- "$MEMORY_SRC_PATH")" ]; then
    exit 0
  fi

  # Refuse to run if the working tree has changes outside MEMORY/.
  # Avoids accidentally bundling unrelated manual chezmoi edits into an
  # auto-commit. User must commit/discard those manually first.
  outside="$(git status --porcelain -- . ":(exclude)$MEMORY_SRC_PATH")"
  if [ -n "$outside" ]; then
    echo "skip: working tree has changes outside $MEMORY_SRC_PATH" >&2
    echo "$outside" >&2
    exit 0
  fi

  git add -A -- "$MEMORY_SRC_PATH"
  git commit -q -m "chore(memory): auto-sync $(date -u +%Y-%m-%dT%H:%MZ)"

  # Several machines share this repo and all push on the same 5 minute cadence,
  # so rebase onto the remote immediately before pushing to narrow the race.
  git fetch --quiet origin main || true
  if ! git rebase --quiet origin/main; then
    git rebase --abort || true
    echo "error: rebase onto origin/main failed, resolve manually" >&2
    exit 1
  fi

  # A lost push race self-heals on the next run, but staying loud here is what
  # surfaces a real breakage (bad credentials, gone remote) instead of hiding it.
  if ! git push --quiet origin main; then
    echo "error: push to origin/main failed" >&2
    exit 1
  fi
''
