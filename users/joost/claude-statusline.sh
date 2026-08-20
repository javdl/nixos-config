#!/usr/bin/env bash
# Claude Code status line, translated from the Starship Rose Pine prompt.
#
# Source of truth for palette, glyphs and module order is
# users/joost/starship.toml (rendered copy: ~/.config/starship.toml).
# Keep this file in sync when that one changes.
#
# Deployed by home-manager via users/joost/home-manager-server.nix to
# ~/.claude/statusline-command.sh. Do NOT edit the deployed copy, it is a
# read-only /nix/store symlink. Edit here and `make switch NIXNAME=<host>`.
#
# Differences from the Starship prompt, all deliberate:
#   - the [fill] module is dropped, since the status line has no reliable
#     terminal width to right-align against
#   - the trailing "\n  󱞪 " prompt character is dropped
#   - a model pill is added, which Starship has no equivalent for

set -u

input=$(cat)

# ---- Rose Pine palette, from [palettes.rose-pine] in starship.toml ----
OVERLAY='38;35;58'    # #26233a
LOVE='235;111;146'    # #eb6f92
GOLD='246;193;119'    # #f6c177
ROSE='235;188;186'    # #ebbcba
PINE='49;116;143'     # #31748f
FOAM='156;207;216'    # #9ccfd8
IRIS='196;167;231'    # #c4a7e7

# Rounded segment caps. Every Starship module here is wrapped in
# "[](fg:overlay) ... [](fg:overlay)", so the caps are drawn in the pill's
# background color against the terminal background.
CAP_L=$''
CAP_R=$''

# text <fg-triplet> <string>   emit text on the pill background
text() { printf '\033[48;2;%sm\033[38;2;%sm%s\033[0m' "$OVERLAY" "$1" "$2"; }

# pill <fg-triplet> <content>  a complete capped segment, trailing space
pill() {
  printf '\033[38;2;%sm%s\033[0m' "$OVERLAY" "$CAP_L"
  text "$1" "$2"
  printf '\033[38;2;%sm%s\033[0m ' "$OVERLAY" "$CAP_R"
}

# ---- [username]: show_always = true ----
pill "$IRIS" " 󰧱 $(whoami) "

# ---- [hostname]: ssh_only = true ----
if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_TTY:-}" ]; then
  pill "$GOLD" " 󰖟 $(hostname -s 2>/dev/null || hostname) "
fi

# ---- [directory]: truncation_length = 3, truncation_symbol = "…/" ----
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -n "$cwd" ] || cwd="$PWD"
disp="${cwd/#$HOME/\~}"

IFS='/' read -ra raw <<< "$disp"
parts=()
for p in "${raw[@]}"; do
  [ -z "$p" ] && continue
  # [directory.substitutions]
  case "$p" in
    Documents) p='󰈙' ;;
    Downloads) p=' ' ;;
    Music)     p=' ' ;;
    Pictures)  p=' ' ;;
  esac
  parts+=("$p")
done
if [ "${#parts[@]}" -gt 3 ]; then
  short_cwd="…/$(IFS=/; printf '%s' "${parts[*]: -3}")"
else
  short_cwd="$disp"
fi
pill "$PINE" " ${short_cwd} "

# ---- [git_branch] and [git_status] ----
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

  if [ -n "$branch" ]; then
    pill "$FOAM" "  ${branch} "

    porcelain=$(git -C "$cwd" status --porcelain 2>/dev/null)
    count() { printf '%s\n' "$porcelain" | grep -cE "$1" || true; }

    staged=$(count '^[MADRC].')
    modified=$(count '^.M')
    deleted=$(count '^(D.|.D)')
    renamed=$(count '^R.')
    untracked=$(count '^\?\?')
    stashed=$(git -C "$cwd" stash list 2>/dev/null | wc -l)

    ahead=0; behind=0
    if git -C "$cwd" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      read -r behind ahead <<< "$(git -C "$cwd" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)"
      behind=${behind:-0}; ahead=${ahead:-0}
    fi

    # Colors per state, matching the individual [git_status] format strings
    # rather than the module's base fg:love.
    if [ $((staged + modified + deleted + renamed + untracked + stashed + ahead + behind)) -gt 0 ]; then
      printf '\033[38;2;%sm%s\033[0m' "$OVERLAY" "$CAP_L"
      [ "$staged"    -gt 0 ] && text "$GOLD" "++(${staged})"
      [ "$modified"  -gt 0 ] && text "$GOLD" "!(${modified})"
      [ "$deleted"   -gt 0 ] && text "$LOVE" "✘(${deleted})"
      [ "$renamed"   -gt 0 ] && text "$IRIS" "»(${renamed})"
      [ "$untracked" -gt 0 ] && text "$GOLD" "?(${untracked})"
      [ "$stashed"   -gt 0 ] && text "$IRIS" '$'
      if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
        text "$IRIS" '⇕['
        text "$FOAM" "⇡(${ahead})"
        text "$ROSE" "⇣(${behind})"
        text "$IRIS" ']'
      elif [ "$ahead" -gt 0 ]; then
        text "$FOAM" "⇡(${ahead})"
      elif [ "$behind" -gt 0 ]; then
        text "$ROSE" "⇣(${behind})"
      fi
      printf '\033[38;2;%sm%s\033[0m ' "$OVERLAY" "$CAP_R"
    else
      # up_to_date = '[ ✓ ](bg:overlay fg:iris)'
      pill "$IRIS" " ✓ "
    fi
  fi
fi

# ---- language and runtime modules ----
# Starship detects by file extension and marker files. Detection is done in a
# subshell so the status line never changes this process's directory, and each
# version probe only runs when its marker is present, keeping renders cheap.
lang() {
  local symbol="$1" version="$2"
  [ -n "$version" ] && pill "$PINE" " ${symbol}${version} "
  return 0
}

has() { ( cd "$cwd" 2>/dev/null && shopt -s nullglob && compgen -G "$1" >/dev/null ); }
marker() { [ -e "${cwd}/$1" ]; }

if has '*.c' || has '*.h'; then
  command -v cc >/dev/null 2>&1 &&
    lang ' ' "$(cc --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
fi
if marker mix.exs; then
  command -v elixir >/dev/null 2>&1 &&
    lang ' ' "$(elixir --version 2>/dev/null | grep -oE 'Elixir [0-9.]+' | grep -oE '[0-9.]+')"
fi
if marker elm.json; then
  command -v elm >/dev/null 2>&1 && lang ' ' "$(elm --version 2>/dev/null)"
fi
if marker go.mod || marker go.sum || has '*.go'; then
  command -v go >/dev/null 2>&1 &&
    lang ' ' "$(go version 2>/dev/null | grep -oE 'go[0-9.]+' | head -1 | tr -d 'go')"
fi
if marker stack.yaml || has '*.cabal'; then
  command -v ghc >/dev/null 2>&1 &&
    lang ' ' "$(ghc --version 2>/dev/null | grep -oE '[0-9.]+$')"
fi
if marker pom.xml || has 'build.gradle*'; then
  command -v java >/dev/null 2>&1 &&
    lang ' ' "$(java -version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
fi
if marker Project.toml || marker Manifest.toml || has '*.jl'; then
  command -v julia >/dev/null 2>&1 &&
    lang ' ' "$(julia --version 2>/dev/null | grep -oE '[0-9.]+$')"
fi
if marker package.json; then
  command -v node >/dev/null 2>&1 && lang '󰎙 ' "$(node --version 2>/dev/null | tr -d 'v')"
fi
if marker nim.cfg || has '*.nim'; then
  command -v nim >/dev/null 2>&1 &&
    lang '󰆥 ' "$(nim --version 2>/dev/null | head -1 | grep -oE '[0-9.]+' | head -1)"
fi
if marker Cargo.toml; then
  command -v rustc >/dev/null 2>&1 &&
    lang ' ' "$(rustc --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
fi
if marker build.sbt || has '*.scala'; then
  command -v scala >/dev/null 2>&1 &&
    lang ' ' "$(scala -version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
fi
if [ -n "${CONDA_DEFAULT_ENV:-}" ]; then
  lang '🅒 ' "$CONDA_DEFAULT_ENV"
fi
if marker requirements.txt || marker pyproject.toml || marker Pipfile || has '*.py'; then
  pybin=$(command -v python3 || command -v python || true)
  [ -n "$pybin" ] &&
    lang ' ' "$("$pybin" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
fi

# ---- model, added: Starship has no equivalent ----
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
[ -n "$model" ] && pill "$IRIS" " ${model} "

# ---- [time]: use_12hr, time_format = "%I:%M%P" ----
# No trailing space, this is the last segment.
printf '\033[38;2;%sm%s\033[0m' "$OVERLAY" "$CAP_L"
text "$ROSE" " $(date '+%I:%M%P') 󰴈 "
printf '\033[38;2;%sm%s\033[0m' "$OVERLAY" "$CAP_R"
