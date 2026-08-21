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

  # The chezmoi source is a plain git repo. A jj repo created with
  # --colocate also has a usable top-level .git, so these commands are
  # correct there too. A non-colocated jj source has no top-level git dir
  # and is skipped loudly rather than failing silently.
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "skip: no git repo in $CHEZMOI_SRC" >&2
    exit 0
  fi

  branch=$(git symbolic-ref --quiet --short HEAD || true)
  if [ "$branch" != "main" ]; then
    echo "skip: chezmoi source is on '$branch', expected main" >&2
    exit 0
  fi

  # Bail out if nothing changed under MEMORY.
  if ! git status --porcelain -- "$MEMORY_SRC_PATH" | grep -q .; then
    exit 0
  fi

  # Refuse to run if the working tree has changes outside MEMORY/.
  # Avoids accidentally bundling unrelated manual chezmoi edits into an
  # auto-commit. User must commit/discard those manually first.
  # Porcelain lines are "XY path", so strip the three-column status prefix.
  outside=$(git status --porcelain | sed 's/^...//' | grep -v "^$MEMORY_SRC_PATH/" || true)
  if [ -n "$outside" ]; then
    echo "skip: working tree has changes outside $MEMORY_SRC_PATH" >&2
    printf '%s\n' "$outside" >&2
    exit 0
  fi

  # Commit before fetching: unlike jj, git cannot rebase a dirty tree, so the
  # jj ordering of fetch-rebase-then-describe does not carry over.
  git add -A -- "$MEMORY_SRC_PATH"
  if git diff --cached --quiet; then
    exit 0
  fi
  git commit -q -m "chore(memory): auto-sync $(date -u +%Y-%m-%dT%H:%MZ)" || exit 0

  # Pull remote changes before pushing to minimize conflicts. Abort a
  # conflicted rebase so the next run starts from a clean tree rather than
  # inheriting a half-finished one; the local commit survives for the retry.
  git fetch --quiet origin 2>/dev/null || true
  if git rev-parse --quiet --verify origin/main >/dev/null 2>&1; then
    if ! git rebase origin/main; then
      git rebase --abort 2>/dev/null || true
      echo "skip: rebase onto origin/main conflicted, commit left unpushed" >&2
      exit 0
    fi
  fi

  git push origin main 2>&1
''
