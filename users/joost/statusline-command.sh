#!/usr/bin/env bash
# Claude Code status line — translated from the Starship Rose Pine prompt.
# Source of truth for palette/format: users/joost/starship.toml in this repo
# (rendered copy: ~/.config/starship.toml). Keep colors/symbols in sync if
# that file changes.
#
# Deployed via home-manager (see home.file in users/joost/home-manager.nix)
# to ~/.claude/statusline-command.sh, referenced by
# ~/.claude/settings.json's statusLine.command.

set -u

input=$(cat)

# ---- Rose Pine palette (users/joost/starship.toml [palettes.rose-pine]) ----
OVERLAY="38;35;58"   # #26233a
LOVE="235;111;146"   # #eb6f92
GOLD="246;193;119"   # #f6c177
ROSE="235;188;186"   # #ebbcba
PINE="49;116;143"    # #31748f
FOAM="156;207;216"   # #9ccfd8
IRIS="196;167;231"   # #c4a7e7

# Rounded segment caps, one on each side of every pill (matches the
# "[<lcap>](fg:overlay)...[<rcap>](fg:overlay)" wrapper starship uses on every
# module). Glyphs taken verbatim from [directory].format in starship.toml.
LCAP=''  # U+E0B6, left half-circle
RCAP=''  # U+E0B4, right half-circle
cap() { printf '\033[38;2;%sm%s\033[0m' "$OVERLAY" "$1"; }

# pill <fg-color-triplet> <content>
pill() {
  local fg="$1" content="$2"
  cap "$LCAP"
  printf '\033[48;2;%sm\033[38;2;%sm%s\033[0m' "$OVERLAY" "$fg" "$content"
  cap "$RCAP"
}

out=""

# ---- [username]: show_always = true, symbol 󰧱 ----
user=$(whoami)
out="${out}$(pill "$IRIS" " 󰧱 ${user} ") "

# ---- [hostname]: ssh_only = true, symbol 󰖟 ----
if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_TTY:-}" ]; then
  host=$(hostname -s 2>/dev/null || hostname)
  out="${out}$(pill "$GOLD" " 󰖟 ${host} ") "
fi

# ---- [directory]: truncation_length = 3, truncation_symbol = "…/" ----
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -n "$cwd" ] || cwd="$PWD"
# The ~ must be escaped: an unquoted ~ on the replacement side is tilde-expanded
# back to $HOME, which makes the substitution a silent no-op.
disp="${cwd/#$HOME/\~}"
IFS='/' read -ra parts <<< "$disp"
clean=()
for p in "${parts[@]}"; do
  [ -z "$p" ] && continue
  case "$p" in
    Documents) p="󰈙" ;;
    Downloads) p=" " ;;
    Music) p=" " ;;
    Pictures) p=" " ;;
  esac
  clean+=("$p")
done
n=${#clean[@]}
if [ "$n" -gt 3 ]; then
  short_cwd="…/$(IFS=/; echo "${clean[*]: -3}")"
else
  short_cwd="$disp"
fi
out="${out}$(pill "$PINE" " ${short_cwd} ") "

# ---- [git_branch] + [git_status] ----
git_dir="$cwd"
if git -C "$git_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$git_dir" symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$git_dir" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    out="${out}$(pill "$FOAM" "  ${branch} ") "

    porcelain=$(git -C "$git_dir" status --porcelain 2>/dev/null)
    staged=$(printf '%s\n' "$porcelain" | grep -cE '^[MADRC]'); staged=${staged:-0}
    modified=$(printf '%s\n' "$porcelain" | grep -cE '^.M'); modified=${modified:-0}
    deleted=$(printf '%s\n' "$porcelain" | grep -cE '^.D|^D'); deleted=${deleted:-0}
    renamed=$(printf '%s\n' "$porcelain" | grep -cE '^R'); renamed=${renamed:-0}
    untracked=$(printf '%s\n' "$porcelain" | grep -cE '^\?\?'); untracked=${untracked:-0}
    stashed=$(git -C "$git_dir" stash list 2>/dev/null | wc -l | tr -d ' ')

    ahead=0
    behind=0
    if git -C "$git_dir" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      read -r behind ahead <<< "$(git -C "$git_dir" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)"
    fi
    behind=${behind:-0}
    ahead=${ahead:-0}

    status_str=""
    [ "$staged" -gt 0 ] && status_str="${status_str}++(${staged})"
    [ "$modified" -gt 0 ] && status_str="${status_str}!(${modified})"
    [ "$deleted" -gt 0 ] && status_str="${status_str}✘(${deleted})"
    [ "$renamed" -gt 0 ] && status_str="${status_str}»(${renamed})"
    [ "$untracked" -gt 0 ] && status_str="${status_str}?(${untracked})"
    [ "$stashed" -gt 0 ] && status_str="${status_str}\$"

    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
      status_str="${status_str}⇕[⇡(${ahead})⇣(${behind})]"
    elif [ "$ahead" -gt 0 ]; then
      status_str="${status_str}⇡(${ahead})"
    elif [ "$behind" -gt 0 ]; then
      status_str="${status_str}⇣(${behind})"
    fi

    [ -n "$status_str" ] && out="${out}$(pill "$LOVE" "${status_str}") "
  fi
fi

# ---- language/runtime modules: only rendered when a marker file for that
# language is present in cwd (mirrors starship's own detection, cheaply) ----
lang_segment() {
  local symbol="$1" version="$2"
  [ -n "$version" ] || return
  out="${out}$(pill "$PINE" " ${symbol}${version} ") "
}

shopt -s nullglob
cd "$cwd" 2>/dev/null || true

if compgen -G "*.c" >/dev/null || compgen -G "*.h" >/dev/null; then
  command -v cc >/dev/null 2>&1 && v=$(cc --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)&& lang_segment " " "$v"
fi
if [ -f mix.exs ]; then
  command -v elixir >/dev/null 2>&1 && v=$(elixir --version 2>/dev/null | grep -oE 'Elixir [0-9.]+' | grep -oE '[0-9.]+') && lang_segment " " "$v"
fi
if [ -f elm.json ]; then
  command -v elm >/dev/null 2>&1 && v=$(elm --version 2>/dev/null) && lang_segment " " "$v"
fi
if [ -f go.mod ] || [ -f go.sum ] || compgen -G "*.go" >/dev/null; then
  command -v go >/dev/null 2>&1 && v=$(go version 2>/dev/null | grep -oE 'go[0-9.]+' | tr -d 'go') && lang_segment " " "$v"
fi
if [ -f stack.yaml ] || compgen -G "*.cabal" >/dev/null; then
  command -v ghc >/dev/null 2>&1 && v=$(ghc --version 2>/dev/null | grep -oE '[0-9.]+$') && lang_segment " " "$v"
fi
if [ -f pom.xml ] || compgen -G "build.gradle*" >/dev/null; then
  command -v java >/dev/null 2>&1 && v=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?') && lang_segment " " "$v"
fi
if [ -f Project.toml ] || [ -f Manifest.toml ] || compgen -G "*.jl" >/dev/null; then
  command -v julia >/dev/null 2>&1 && v=$(julia --version 2>/dev/null | grep -oE '[0-9.]+$') && lang_segment " " "$v"
fi
if [ -f package.json ]; then
  command -v node >/dev/null 2>&1 && v=$(node --version 2>/dev/null | tr -d 'v') && lang_segment "󰎙 " "$v"
fi
if [ -f nim.cfg ] || compgen -G "*.nim" >/dev/null; then
  command -v nim >/dev/null 2>&1 && v=$(nim --version 2>/dev/null | head -1 | grep -oE '[0-9.]+' | head -1) && lang_segment "󰆥 " "$v"
fi
if [ -f Cargo.toml ]; then
  command -v rustc >/dev/null 2>&1 && v=$(rustc --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) && lang_segment " " "$v"
fi
if [ -f build.sbt ] || compgen -G "*.scala" >/dev/null; then
  command -v scala >/dev/null 2>&1 && v=$(scala -version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) && lang_segment " " "$v"
fi
if [ -n "${CONDA_DEFAULT_ENV:-}" ]; then
  lang_segment "🅒 " "$CONDA_DEFAULT_ENV"
fi
if [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f Pipfile ] || compgen -G "*.py" >/dev/null; then
  pybin=$(command -v python3 || command -v python)
  if [ -n "$pybin" ]; then
    v=$("$pybin" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    lang_segment " " "$v"
  fi
fi
shopt -u nullglob

# ---- Claude Code model (no starship equivalent — added per request) ----
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
[ -n "$model" ] && out="${out}$(pill "$IRIS" " ${model} ") "

# ---- [time]: 12h clock, lowercase am/pm, symbol 󰴈 ----
time_str=$(date '+%I:%M%P')
out="${out}$(pill "$ROSE" " ${time_str} 󰴈 ")"

printf '%s' "$out"
