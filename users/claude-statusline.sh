#!/usr/bin/env bash
# Claude Code status line — Rose Pine theme
# Deployed via home-manager to ~/.claude/statusline-command.sh

# Rose Pine palette
IRIS='\033[38;2;196;167;231m'    # #c4a7e7 - purple (username, session)
PINE='\033[38;2;49;116;143m'     # #31748f - teal (directory)
FOAM='\033[38;2;156;207;216m'    # #9ccfd8 - light blue (git branch)
GOLD='\033[38;2;246;193;119m'    # #f6c177 - yellow (git modified/staged)
LOVE='\033[38;2;235;111;146m'    # #eb6f92 - pink (git conflicts)
ROSE='\033[38;2;235;188;186m'    # #ebbcba - soft pink (time, context)
RESET='\033[0m'

input=$(cat)

# Extract fields from JSON
user=$(whoami)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
session=$(echo "$input" | jq -r '.session_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Shorten cwd: replace $HOME with ~, truncate to last 3 parts
if [ -n "$cwd" ]; then
  home_dir="$HOME"
  short_cwd="${cwd/#$home_dir/~}"
  parts=$(echo "$short_cwd" | tr '/' '\n' | grep -v '^$')
  count=$(echo "$parts" | wc -l | tr -d ' ')
  if [ "$count" -gt 3 ]; then
    short_cwd="…/$(echo "$parts" | tail -3 | tr '\n' '/' | sed 's|/$||')"
  fi
else
  short_cwd=$(pwd | sed "s|$HOME|~|")
fi

# Git branch and status
git_info=""
if git -C "${cwd:-$PWD}" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "${cwd:-$PWD}" symbolic-ref --short HEAD 2>/dev/null \
           || git -C "${cwd:-$PWD}" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    status_output=$(git -C "${cwd:-$PWD}" status --porcelain 2>/dev/null)
    modified=$(echo "$status_output" | grep -c '^ M\| M' 2>/dev/null || echo 0)
    staged=$(echo "$status_output" | grep -c '^M\|^A\|^D\|^R\|^C' 2>/dev/null || echo 0)
    untracked=$(echo "$status_output" | grep -c '^??' 2>/dev/null || echo 0)

    git_info=" ${FOAM} ${branch}${RESET}"
    if [ "$staged" -gt 0 ]; then
      git_info="${git_info} ${GOLD}++${staged}${RESET}"
    fi
    if [ "$modified" -gt 0 ]; then
      git_info="${git_info} ${GOLD}!${modified}${RESET}"
    fi
    if [ "$untracked" -gt 0 ]; then
      git_info="${git_info} ${GOLD}?${untracked}${RESET}"
    fi
  fi
fi

# Context window usage (color-coded)
ctx_info=""
if [ -n "$used_pct" ]; then
  used_int=${used_pct%.*}
  if [ "$used_int" -ge 80 ]; then
    ctx_info=" ${LOVE}ctx:${used_int}%${RESET}"
  elif [ "$used_int" -ge 50 ]; then
    ctx_info=" ${GOLD}ctx:${used_int}%${RESET}"
  else
    ctx_info=" ${ROSE}ctx:${used_int}%${RESET}"
  fi
fi

# Model info
model_info=""
if [ -n "$model" ]; then
  model_info=" ${IRIS}${model}${RESET}"
fi

# Session name
session_info=""
if [ -n "$session" ]; then
  session_info=" ${IRIS}[${session}]${RESET}"
fi

# Time
time_str=$(date +%I:%M%p | tr '[:upper:]' '[:lower:]')

# Compose the status line
printf "${IRIS} ${user}${RESET} ${PINE}${short_cwd}${RESET}${git_info}${model_info}${session_info}${ctx_info} ${ROSE}${time_str}${RESET}"
