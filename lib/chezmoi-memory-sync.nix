# Shared chezmoi-memory-sync script. Re-adds ~/.claude/MEMORY into the chezmoi
# source repo, then commits + pushes via jj if anything under MEMORY changed.
#
# Consumed by:
#   - hosts/mac-shared.nix    -> launchd.user.agents.chezmoi-memory-sync (Darwin)
#   - users/joost/home-manager-server.nix -> systemd.user.{service,timer}.chezmoi-memory-sync (loom)
#
# Both schedule it every 5 minutes. Body is identical across platforms.
pkgs: pkgs.writeShellScript "chezmoi-memory-sync" ''
  set -u

  # systemd user services start with a minimal PATH that lacks chezmoi/jj/grep.
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

  # Bail out if nothing changed under MEMORY.
  if ! jj diff --stat -- "$MEMORY_SRC_PATH" 2>/dev/null | grep -q .; then
    exit 0
  fi

  # Refuse to run if the working copy has changes outside MEMORY/.
  # Avoids accidentally bundling unrelated manual chezmoi edits into an
  # auto-commit. User must commit/discard those manually first.
  if jj diff --name-only 2>/dev/null | grep -v "^$MEMORY_SRC_PATH/" | grep -q .; then
    echo "skip: working copy has changes outside $MEMORY_SRC_PATH" >&2
    jj diff --name-only | grep -v "^$MEMORY_SRC_PATH/" >&2
    exit 0
  fi

  # Pull remote changes first to minimize conflicts.
  jj git fetch 2>/dev/null || true
  jj rebase -d main 2>/dev/null || true

  jj describe -m "chore(memory): auto-sync $(date -u +%Y-%m-%dT%H:%MZ)"
  jj bookmark set main -r @
  jj git push 2>&1
''
