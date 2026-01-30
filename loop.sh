#!/usr/bin/env bash
#
# beads-loop v3 - Production-grade loop runner for Claude Code
#
# Features:
#   - Real-time TUI dashboard
#   - Session persistence & resume
#   - Live token streaming & cost tracking
#   - Webhooks & integrations
#   - Interactive approval mode
#   - Rich jj diff display
#   - Automatic rate limit handling
#   - Report generation
#
set -euo pipefail

readonly VERSION="3.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ═══════════════════════════════════════════════════════════════════════════════
# Constants & Defaults
# ═══════════════════════════════════════════════════════════════════════════════

readonly STATE_DIR=".ralph"
readonly CONFIG_FILE=".ralph/config.toml"
readonly HISTORY_FILE="$STATE_DIR/history.jsonl"

# Default configuration
declare -A CONFIG=(
    [mode]="build"
    [max_iterations]=500
    [model]="opus"
    [delay]=3
    [max_retries]=2
    [retry_delay]=10
    [auto_stop_empty]=true
    [auto_stop_failures]=3
    [push_enabled]=true
    [notifications]=true
    [sound]=false
    [interactive]=false
    [webhook_url]=""
    [rate_limit_pause]=60
    [checkpoint_interval]=5
    [verbose]=false
    [review_enabled]=true
    [review_model]="gpt-5.2-codex"
    [review_max_revisions]=5
    [epic]=""
)

# Runtime state
declare -A STATE=(
    [session_id]=""
    [iteration]=0
    [consecutive_failures]=0
    [total_tokens]=0
    [total_cost]="0"
    [start_time]=0
    [status]="initializing"
    [paused]=false
    [interrupted]=false
    [review_passes]=0
    [review_revisions]=0
    [review_skipped]=0
)

# ═══════════════════════════════════════════════════════════════════════════════
# Terminal & Colors
# ═══════════════════════════════════════════════════════════════════════════════

setup_terminal() {
    # Check if we have a real terminal
    if [[ -t 1 ]]; then
        HAS_TTY=true
        TERM_COLS=$(tput cols 2>/dev/null || echo 80)
        TERM_ROWS=$(tput lines 2>/dev/null || echo 24)
    else
        HAS_TTY=false
        TERM_COLS=80
        TERM_ROWS=24
    fi

    # Colors (with fallback for non-color terminals)
    if [[ "${TERM:-}" != "dumb" ]] && [[ "$HAS_TTY" == true ]]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_ITALIC=$'\033[3m'
        C_UNDER=$'\033[4m'
        C_RED=$'\033[38;5;203m'
        C_GREEN=$'\033[38;5;114m'
        C_YELLOW=$'\033[38;5;221m'
        C_BLUE=$'\033[38;5;69m'
        C_MAGENTA=$'\033[38;5;176m'
        C_CYAN=$'\033[38;5;80m'
        C_ORANGE=$'\033[38;5;215m'
        C_GRAY=$'\033[38;5;245m'
        C_WHITE=$'\033[38;5;255m'
        C_BG_DARK=$'\033[48;5;236m'
    else
        C_RESET="" C_BOLD="" C_DIM="" C_ITALIC="" C_UNDER=""
        C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA=""
        C_CYAN="" C_ORANGE="" C_GRAY="" C_WHITE="" C_BG_DARK=""
    fi
}

# Symbols (with ASCII fallback)
setup_symbols() {
    if [[ "${LANG:-}" == *UTF-8* ]] || [[ "${LC_ALL:-}" == *UTF-8* ]]; then
        SYM_CHECK="✓"
        SYM_CROSS="✗"
        SYM_ARROW="▸"
        SYM_BULLET="●"
        SYM_CIRCLE="○"
        SYM_SPARK="✦"
        SYM_WARN="⚠"
        SYM_INFO="ℹ"
        SYM_PLAY="▶"
        SYM_PAUSE="⏸"
        SYM_STOP="⏹"
        SYM_CLOCK="◷"
        SYM_GEAR="⚙"
        SYM_GRAPH="▁▂▃▄▅▆▇█"
        SYM_SPIN="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    else
        SYM_CHECK="+"
        SYM_CROSS="x"
        SYM_ARROW=">"
        SYM_BULLET="*"
        SYM_CIRCLE="o"
        SYM_SPARK="*"
        SYM_WARN="!"
        SYM_INFO="i"
        SYM_PLAY=">"
        SYM_PAUSE="||"
        SYM_STOP="[]"
        SYM_CLOCK="@"
        SYM_GEAR="#"
        SYM_GRAPH="12345678"
        SYM_SPIN="-\\|/"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Logging System
# ═══════════════════════════════════════════════════════════════════════════════

LOG_FILE=""
METRICS_FILE=""

init_logging() {
    local session_dir="$STATE_DIR/sessions/${STATE[session_id]}"
    mkdir -p "$session_dir"

    LOG_FILE="$session_dir/session.log"
    METRICS_FILE="$session_dir/metrics.jsonl"

    # Rotate old logs if too large (>10MB)
    if [[ -f "$LOG_FILE" ]]; then
        local size
        size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        [[ "$size" -gt 10485760 ]] && mv "$LOG_FILE" "$LOG_FILE.$(date +%s).bak"
    fi
}

log() {
    local level="${1:-INFO}"
    local msg="${2:-}"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')

    # Strip colors for file
    local clean_msg=$(echo -e "$msg" | sed 's/\x1b\[[0-9;]*m//g')
    echo "[$ts] [$level] $clean_msg" >> "$LOG_FILE"

    # Console output based on level
    case "$level" in
        DEBUG)
            [[ "${CONFIG[verbose]:-false}" == true ]] && echo -e "${C_DIM}$msg${C_RESET}" ;;
        INFO)
            echo -e "$msg" ;;
        WARN)
            echo -e "${C_YELLOW}${SYM_WARN} $msg${C_RESET}" ;;
        ERROR)
            echo -e "${C_RED}${SYM_CROSS} $msg${C_RESET}" >&2 ;;
        SUCCESS)
            echo -e "${C_GREEN}${SYM_CHECK} $msg${C_RESET}" ;;
    esac
}

log_metric() {
    local metric="$1"
    local value="$2"
    local tags="${3:-}"

    local json="{\"ts\":$(date +%s),\"iteration\":${STATE[iteration]},\"metric\":\"$metric\",\"value\":$value"
    [[ -n "$tags" ]] && json="$json,\"tags\":$tags"
    json="$json}"

    echo "$json" >> "$METRICS_FILE"
}

# ═══════════════════════════════════════════════════════════════════════════════
# TUI Components
# ═══════════════════════════════════════════════════════════════════════════════

cursor_save() { [[ "$HAS_TTY" == true ]] && tput sc || true; }
cursor_restore() { [[ "$HAS_TTY" == true ]] && tput rc || true; }
cursor_hide() { [[ "$HAS_TTY" == true ]] && tput civis 2>/dev/null || true; }
cursor_show() { [[ "$HAS_TTY" == true ]] && tput cnorm 2>/dev/null || true; }
clear_line() { [[ "$HAS_TTY" == true ]] && printf '\r%*s\r' "$TERM_COLS" '' || true; }
move_to() { [[ "$HAS_TTY" == true ]] && tput cup "$1" "$2" || true; }

# Progress bar
progress_bar() {
    local current=$1
    local total=$2
    local width=${3:-40}
    local label="${4:-}"

    if [[ $total -eq 0 ]]; then
        printf "${C_DIM}[%*s]${C_RESET}" "$width" ""
        return
    fi

    local pct=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "${C_CYAN}["
    [[ $filled -gt 0 ]] && printf '%*s' "$filled" '' | tr ' ' '█'
    [[ $empty -gt 0 ]] && printf "${C_DIM}%*s${C_CYAN}" "$empty" '' | tr ' ' '░'
    printf "]${C_RESET} %3d%%" "$pct"
    [[ -n "$label" ]] && printf " ${C_DIM}%s${C_RESET}" "$label"
}

# Sparkline from array of values
sparkline() {
    local -a values=("$@")
    local max=1

    for v in "${values[@]}"; do
        [[ $v -gt $max ]] && max=$v
    done

    local chars="${SYM_GRAPH}"
    local result=""
    for v in "${values[@]}"; do
        local idx=$((v * 7 / max))
        result+="${chars:idx:1}"
    done
    echo "$result"
}

# Spinner with message
declare SPINNER_PID=""

spinner_start() {
    local msg="$1"
    [[ "$HAS_TTY" != true ]] && return

    cursor_hide
    (
        local i=0
        local spin="${SYM_SPIN}"
        while true; do
            printf "\r  ${C_CYAN}%s${C_RESET} %s" "${spin:i++%${#spin}:1}" "$msg"
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
}

spinner_stop() {
    [[ -n "$SPINNER_PID" ]] && kill "$SPINNER_PID" 2>/dev/null && wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    clear_line
    cursor_show
}

# ═══════════════════════════════════════════════════════════════════════════════
# Dashboard
# ═══════════════════════════════════════════════════════════════════════════════

draw_header() {
    local width=$TERM_COLS
    local title=" BEADS LOOP v$VERSION "
    local pad=$(( (width - ${#title}) / 2 ))

    echo -e "${C_BG_DARK}${C_WHITE}"
    printf '%*s%s%*s' "$pad" '' "$title" "$((width - pad - ${#title}))" ''
    echo -e "${C_RESET}"
}

draw_status_bar() {
    local status_icon status_color
    case "${STATE[status]}" in
        running)    status_icon="$SYM_PLAY"; status_color="$C_GREEN" ;;
        paused)     status_icon="$SYM_PAUSE"; status_color="$C_YELLOW" ;;
        failed)     status_icon="$SYM_CROSS"; status_color="$C_RED" ;;
        complete)   status_icon="$SYM_CHECK"; status_color="$C_GREEN" ;;
        *)          status_icon="$SYM_CIRCLE"; status_color="$C_GRAY" ;;
    esac

    local elapsed=$(($(date +%s) - STATE[start_time]))
    local elapsed_fmt=$(format_duration $elapsed)

    printf "${C_DIM}│${C_RESET} "
    printf "${status_color}%s %s${C_RESET}" "$status_icon" "${STATE[status]^^}"
    printf " ${C_DIM}│${C_RESET} "
    printf "${C_CYAN}%s${C_RESET} iter %d" "$SYM_CLOCK" "${STATE[iteration]}"
    [[ ${CONFIG[max_iterations]} -gt 0 ]] && printf "/${CONFIG[max_iterations]}"
    printf " ${C_DIM}│${C_RESET} "
    printf "%s %s" "$SYM_CLOCK" "$elapsed_fmt"
    printf " ${C_DIM}│${C_RESET} "
    printf "${C_GREEN}$%s${C_RESET}" "${STATE[total_cost]}"
    if [[ "${CONFIG[review_enabled]}" == true ]]; then
        printf " ${C_DIM}│${C_RESET} "
        printf "${C_GREEN}%d${C_RESET}${C_DIM}S${C_RESET}" "${STATE[review_passes]}"
        printf "/${C_YELLOW}%d${C_RESET}${C_DIM}R${C_RESET}" "${STATE[review_revisions]}"
        [[ ${STATE[review_skipped]} -gt 0 ]] && printf "/${C_GRAY}%d${C_RESET}${C_DIM}?${C_RESET}" "${STATE[review_skipped]}"
    fi
    printf " ${C_DIM}│${C_RESET}"
    echo ""
}

draw_box() {
    local title="$1"
    local content="$2"
    local width=${3:-$((TERM_COLS - 4))}

    echo -e "${C_DIM}┌─${C_RESET}${C_BOLD} $title ${C_RESET}${C_DIM}$(printf '─%.0s' $(seq 1 $((width - ${#title} - 4))))┐${C_RESET}"
    echo -e "$content" | while IFS= read -r line; do
        printf "${C_DIM}│${C_RESET} %-$((width-2))s ${C_DIM}│${C_RESET}\n" "$line"
    done
    echo -e "${C_DIM}└$(printf '─%.0s' $(seq 1 $((width))))┘${C_RESET}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Utilities
# ═══════════════════════════════════════════════════════════════════════════════

format_duration() {
    local seconds=$1
    if [[ $seconds -lt 60 ]]; then
        printf '%ds' "$seconds"
    elif [[ $seconds -lt 3600 ]]; then
        printf '%dm%02ds' $((seconds/60)) $((seconds%60))
    else
        printf '%dh%02dm%02ds' $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
    fi
}

format_number() {
    local num=$1
    if [[ $num -lt 1000 ]]; then
        echo "$num"
    elif [[ $num -lt 1000000 ]]; then
        printf '%.1fK' "$(bc <<< "scale=1; $num/1000")"
    else
        printf '%.2fM' "$(bc <<< "scale=2; $num/1000000")"
    fi
}

format_bytes() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        printf '%.1fKB' "$(bc <<< "scale=1; $bytes/1024")"
    else
        printf '%.1fMB' "$(bc <<< "scale=1; $bytes/1048576")"
    fi
}

json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Notifications & Integrations
# ═══════════════════════════════════════════════════════════════════════════════

notify() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"  # low, normal, critical

    [[ "${CONFIG[notifications]}" != true ]] && return

    # Desktop notification
    if [[ "$(uname)" == "Darwin" ]]; then
        osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
    elif command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
    fi

    # Sound
    if [[ "${CONFIG[sound]}" == true ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
        elif command -v paplay &>/dev/null; then
            paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null &
        fi
    fi
}

send_webhook() {
    local event="$1"
    local payload="$2"

    [[ -z "${CONFIG[webhook_url]}" ]] && return

    local full_payload=$(cat <<EOF
{
    "event": "$event",
    "session_id": "${STATE[session_id]}",
    "iteration": ${STATE[iteration]},
    "timestamp": "$(date -Iseconds)",
    "data": $payload
}
EOF
)

    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$full_payload" \
        "${CONFIG[webhook_url]}" &>/dev/null &
}

# ═══════════════════════════════════════════════════════════════════════════════
# VCS Operations (jj/Jujutsu)
# ═══════════════════════════════════════════════════════════════════════════════

vcs_branch() {
    jj log -r @ --no-graph -T 'bookmarks' 2>/dev/null | head -1 || echo "none"
}

vcs_commit_short() {
    jj log -r @ --no-graph -T 'change_id.shortest(8)' 2>/dev/null || echo "unknown"
}

vcs_is_dirty() {
    # In jj, the working copy is always a commit; check if it has changes
    local status
    status=$(jj diff --stat 2>/dev/null)
    [[ -n "$status" ]]
}

vcs_changes_summary() {
    local from_change="$1"
    local to_change="${2:-@}"

    [[ "$from_change" == "$to_change" ]] && return

    local output=""
    local files
    files=$(jj diff --from "$from_change" --to "$to_change" --name-only 2>/dev/null)
    local file_count=$(echo "$files" | grep -c . 2>/dev/null || echo 0)

    [[ $file_count -eq 0 ]] && return

    output+="${C_BOLD}Changes:${C_RESET}\n"

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        local stat
        stat=$(jj diff --from "$from_change" --to "$to_change" --stat -- "$file" 2>/dev/null | head -1)
        local added=$(echo "$stat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
        local removed=$(echo "$stat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)

        # File type icon
        local icon="📄"
        case "${file##*.}" in
            rs) icon="🦀" ;;
            py) icon="🐍" ;;
            ts|tsx) icon="📘" ;;
            js|jsx) icon="📒" ;;
            go) icon="🐹" ;;
            rb) icon="💎" ;;
            md) icon="📝" ;;
            toml|yaml|yml|json) icon="⚙️ " ;;
            sh|bash) icon="🐚" ;;
            sql) icon="🗃️ " ;;
            html|css) icon="🌐" ;;
            Dockerfile|docker*) icon="🐳" ;;
        esac

        output+="  $icon ${C_WHITE}$file${C_RESET}"
        [[ -n "$added" ]] && [[ "$added" != "0" ]] && output+=" ${C_GREEN}+$added${C_RESET}"
        [[ -n "$removed" ]] && [[ "$removed" != "0" ]] && output+=" ${C_RED}-$removed${C_RESET}"
        output+="\n"
    done <<< "$(echo "$files" | head -8)"

    [[ $file_count -gt 8 ]] && output+="  ${C_DIM}... and $((file_count - 8)) more files${C_RESET}\n"

    # Summary stats
    local total_stats
    total_stats=$(jj diff --from "$from_change" --to "$to_change" --stat 2>/dev/null | tail -1)
    [[ -n "$total_stats" ]] && output+="${C_DIM}  $total_stats${C_RESET}\n"

    echo -e "$output"
}

vcs_push() {
    [[ "${CONFIG[push_enabled]}" != true ]] && return 0

    if jj git push 2>/dev/null; then
        log DEBUG "Pushed via jj git push"
        return 0
    fi

    log WARN "Failed to push to remote"
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# Beads Integration
# ═══════════════════════════════════════════════════════════════════════════════

beads_check() {
    if [[ ! -d ".beads" ]]; then
        log ERROR "Beads not initialized. Run: ${C_CYAN}bd init${C_RESET}"
        return 1
    fi

    if ! command -v bd &>/dev/null; then
        log ERROR "bd command not found"
        return 1
    fi

    return 0
}

beads_ready_count() {
    local epic_flag=""
    [[ -n "${CONFIG[epic]}" ]] && epic_flag="--parent ${CONFIG[epic]}"
    bd ready --json $epic_flag 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0"
}

beads_ready_items() {
    local limit=${1:-5}
    local epic_flag=""
    [[ -n "${CONFIG[epic]}" ]] && epic_flag="--parent ${CONFIG[epic]}"
    bd ready --json $epic_flag 2>/dev/null | jq -r ".[:$limit][] | \"  ${SYM_BULLET} \" + .title" 2>/dev/null || \
        bd ready --limit "$limit" $epic_flag 2>/dev/null
}

beads_sync() {
    bd sync 2>/dev/null || true
}

beads_stats() {
    bd stats 2>/dev/null || echo "No stats available"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Claude Execution
# ═══════════════════════════════════════════════════════════════════════════════

# Stream Claude output and capture metrics in real-time
run_claude_streaming() {
    local prompt_file="$1"
    local output_file="$2"

    local temp_json=$(mktemp)
    local exit_code=0

    # Run Claude with stream-json, process output
    # Note: We capture PIPESTATUS immediately after pipeline to get claude's exit code
    cat "$prompt_file" | claude -p \
        --dangerously-skip-permissions \
        --model "${CONFIG[model]}" \
        --output-format stream-json \
        --verbose 2>&1 | tee "$temp_json" | \
    while IFS= read -r line; do
        # Try to parse as JSON
        if echo "$line" | jq -e '.type' &>/dev/null; then
            local type=$(echo "$line" | jq -r '.type')

            case "$type" in
                content_block_delta)
                    # Extract and print text content
                    local text=$(echo "$line" | jq -r '.delta.text // empty' 2>/dev/null)
                    [[ -n "$text" ]] && printf '%s' "$text"
                    ;;
                message_start)
                    # Could extract model info here
                    ;;
                message_delta)
                    # Extract token usage
                    local usage=$(echo "$line" | jq -r '.usage // empty' 2>/dev/null)
                    [[ -n "$usage" ]] && echo "$usage" >> "$output_file.usage"
                    ;;
            esac
        else
            # Non-JSON line (verbose output), save to log
            echo "$line" >> "$output_file.verbose"
        fi
    done
    # Capture claude's exit code from PIPESTATUS (index 1: cat=0, claude=1, tee=2, while=3)
    # Must be done immediately - any command resets PIPESTATUS
    exit_code=${PIPESTATUS[1]}

    # Move temp file to final location
    mv "$temp_json" "$output_file.json"

    return $exit_code
}

# Parse token usage from Claude output
parse_claude_metrics() {
    local output_file="$1"

    local input_tokens=0
    local output_tokens=0

    # Try to get from usage file first
    if [[ -f "$output_file.usage" ]]; then
        input_tokens=$(jq -s 'map(.input_tokens // 0) | add' "$output_file.usage" 2>/dev/null || echo 0)
        output_tokens=$(jq -s 'map(.output_tokens // 0) | add' "$output_file.usage" 2>/dev/null || echo 0)
    fi

    # Fallback: parse from verbose output
    if [[ $input_tokens -eq 0 ]] && [[ -f "$output_file.verbose" ]]; then
        input_tokens=$(grep -oE 'input.?tokens[:\s]+([0-9,]+)' "$output_file.verbose" 2>/dev/null | grep -oE '[0-9,]+' | tr -d ',' | tail -1 || echo 0)
        output_tokens=$(grep -oE 'output.?tokens[:\s]+([0-9,]+)' "$output_file.verbose" 2>/dev/null | grep -oE '[0-9,]+' | tr -d ',' | tail -1 || echo 0)
    fi

    input_tokens=${input_tokens:-0}
    output_tokens=${output_tokens:-0}

    local total=$((input_tokens + output_tokens))

    # Cost calculation (Opus pricing: $15/M input, $75/M output)
    local cost=$(bc <<< "scale=4; ($input_tokens * 0.015 + $output_tokens * 0.075) / 1000" 2>/dev/null || echo "0")

    STATE[total_tokens]=$((STATE[total_tokens] + total))
    STATE[total_cost]=$(bc <<< "scale=2; ${STATE[total_cost]} + $cost" 2>/dev/null || echo "${STATE[total_cost]}")

    log_metric "tokens_input" "$input_tokens"
    log_metric "tokens_output" "$output_tokens"
    log_metric "cost" "$cost"

    echo "$total|$cost"
}

# Run Claude with retries
run_claude_with_retry() {
    local prompt_file="$1"
    local output_file="$2"
    local attempt=1
    local max_attempts=$((CONFIG[max_retries] + 1))

    while [[ $attempt -le $max_attempts ]]; do
        [[ "${STATE[interrupted]}" == true ]] && return 1

        if [[ $attempt -gt 1 ]]; then
            log WARN "Retry $((attempt-1))/${CONFIG[max_retries]} in ${CONFIG[retry_delay]}s..."
            sleep "${CONFIG[retry_delay]}" || true
            [[ "${STATE[interrupted]}" == true ]] && return 1
        fi

        local exit_code=0

        echo ""
        echo -e "${C_DIM}$(printf '─%.0s' $(seq 1 $TERM_COLS))${C_RESET}"

        if run_claude_streaming "$prompt_file" "$output_file"; then
            echo ""
            echo -e "${C_DIM}$(printf '─%.0s' $(seq 1 $TERM_COLS))${C_RESET}"
            return 0
        else
            exit_code=$?
        fi

        [[ "${STATE[interrupted]}" == true ]] && return 1

        echo ""

        # Check for rate limit
        if grep -qi "rate.limit\|429\|too.many.requests" "$output_file.verbose" 2>/dev/null; then
            log WARN "Rate limited. Waiting ${CONFIG[rate_limit_pause]}s..."
            sleep "${CONFIG[rate_limit_pause]}" || true
            [[ "${STATE[interrupted]}" == true ]] && return 1
        fi

        log ERROR "Claude exited with code $exit_code"
        attempt=$((attempt + 1))
    done

    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# Review Phase
# ═══════════════════════════════════════════════════════════════════════════════

# Run review using codex exec. Returns 0=SHIP, 1=REVISE, 2=parse failure, 3=fatal error
run_review() {
    local iter_log="$1"
    local review_file="${iter_log}.review"
    local feedback_file="${iter_log}.review_feedback"

    local review_model="${CONFIG[review_model]}"
    local prompt_file="${SCRIPT_DIR}/PROMPT_review.md"

    [[ ! -f "$prompt_file" ]] && { log WARN "Review prompt not found: $prompt_file"; return 2; }

    # Check that codex command exists
    if ! command -v codex &>/dev/null; then
        log ERROR "codex command not found - install it or use --no-review"
        return 3
    fi

    # Build review input: jj diff + task context
    local review_input
    review_input=$(mktemp)
    {
        echo "## Diff (latest changes)"
        echo '```'
        jj diff -r @- 2>/dev/null || jj diff 2>/dev/null || echo "(no diff available)"
        echo '```'
        echo ""
        echo "## In-progress tasks"
        bd list --status in_progress 2>/dev/null || echo "(none)"
        echo ""
        cat "$prompt_file"
    } > "$review_input"

    log INFO "  ${C_MAGENTA}${SYM_GEAR} Running review${C_RESET} ${C_DIM}(${review_model})${C_RESET}"

    # Invoke codex exec in read-only sandbox, full-auto mode
    local exit_code=0
    if codex exec \
        --model "$review_model" \
        --sandbox read-only \
        --full-auto \
        < "$review_input" \
        > "$review_file" 2>&1; then
        exit_code=0
    else
        exit_code=$?
        log WARN "codex exec exited with code $exit_code"
    fi

    rm -f "$review_input"

    # Detect fatal errors (auth failures, connection errors, unsupported model)
    # These should stop the loop, not silently skip review
    if [[ $exit_code -ne 0 ]] && [[ -f "$review_file" ]]; then
        if grep -qiE '401 Unauthorized|403 Forbidden|exceeded retry limit|not supported|authentication|invalid.*api.*key' "$review_file"; then
            log ERROR "Review failed with auth/connection error (codex exit code $exit_code):"
            grep -iE 'ERROR:|Unauthorized|Forbidden|exceeded|not supported|authentication|invalid' "$review_file" | head -3 | while IFS= read -r line; do
                log ERROR "  $line"
            done
            return 3
        fi
    fi

    # Check if output file has content
    if [[ ! -s "$review_file" ]]; then
        if [[ $exit_code -ne 0 ]]; then
            log ERROR "Review produced no output (codex exit code $exit_code)"
            return 3
        fi
        log WARN "Review produced no output"
        return 2
    fi

    # Parse RESULT line
    local result_line
    result_line=$(grep -E '^RESULT:\s*(SHIP|REVISE)' "$review_file" | tail -1)

    if [[ -z "$result_line" ]]; then
        log WARN "Could not parse review result from output"
        return 2
    fi

    if echo "$result_line" | grep -q 'SHIP'; then
        log SUCCESS "Review: ${C_GREEN}SHIP${C_RESET}"
        return 0
    else
        log WARN "Review: ${C_YELLOW}REVISE${C_RESET}"
        # Save feedback (everything before the RESULT line)
        sed '/^RESULT:/d' "$review_file" > "$feedback_file"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Session Management
# ═══════════════════════════════════════════════════════════════════════════════

session_new() {
    STATE[session_id]=$(date +%Y%m%d_%H%M%S)_$$
    STATE[start_time]=$(date +%s)
    STATE[iteration]=0
    STATE[consecutive_failures]=0
    STATE[total_tokens]=0
    STATE[total_cost]="0"
    STATE[status]="initializing"

    mkdir -p "$STATE_DIR/sessions/${STATE[session_id]}"

    session_save
}

session_save() {
    local session_file="$STATE_DIR/sessions/${STATE[session_id]}/state.json"

    cat > "$session_file" <<EOF
{
    "session_id": "${STATE[session_id]}",
    "iteration": ${STATE[iteration]},
    "consecutive_failures": ${STATE[consecutive_failures]},
    "total_tokens": ${STATE[total_tokens]},
    "total_cost": ${STATE[total_cost]},
    "start_time": ${STATE[start_time]},
    "status": "${STATE[status]}",
    "review": {
        "enabled": ${CONFIG[review_enabled]},
        "model": "${CONFIG[review_model]}",
        "passes": ${STATE[review_passes]},
        "revisions": ${STATE[review_revisions]},
        "skipped": ${STATE[review_skipped]}
    },
    "config": {
        "mode": "${CONFIG[mode]}",
        "model": "${CONFIG[model]}",
        "max_iterations": ${CONFIG[max_iterations]}
    },
    "vcs": {
        "bookmark": "$(vcs_branch)",
        "change": "$(vcs_commit_short)"
    },
    "updated_at": "$(date -Iseconds)"
}
EOF

    # Also update latest symlink
    ln -sf "sessions/${STATE[session_id]}" "$STATE_DIR/latest"
}

session_load() {
    local session_id="$1"
    local session_file="$STATE_DIR/sessions/$session_id/state.json"

    [[ ! -f "$session_file" ]] && return 1

    STATE[session_id]="$session_id"
    STATE[iteration]=$(jq -r '.iteration' "$session_file")
    STATE[consecutive_failures]=$(jq -r '.consecutive_failures' "$session_file")
    STATE[total_tokens]=$(jq -r '.total_tokens' "$session_file")
    STATE[total_cost]=$(jq -r '.total_cost' "$session_file")
    STATE[start_time]=$(jq -r '.start_time' "$session_file")
    STATE[status]=$(jq -r '.status' "$session_file")

    return 0
}

session_list() {
    echo -e "${C_BOLD}Recent sessions:${C_RESET}\n"

    for dir in $(ls -dt "$STATE_DIR/sessions"/*/ 2>/dev/null | head -10); do
        local state_file="$dir/state.json"
        [[ ! -f "$state_file" ]] && continue

        local sid=$(jq -r '.session_id' "$state_file")
        local status=$(jq -r '.status' "$state_file")
        local iters=$(jq -r '.iteration' "$state_file")
        local updated=$(jq -r '.updated_at' "$state_file")

        local status_color="$C_GRAY"
        case "$status" in
            complete) status_color="$C_GREEN" ;;
            running) status_color="$C_CYAN" ;;
            failed) status_color="$C_RED" ;;
        esac

        printf "  ${C_BOLD}%s${C_RESET}  ${status_color}%-10s${C_RESET}  %d iters  ${C_DIM}%s${C_RESET}\n" \
            "$sid" "$status" "$iters" "$updated"
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Loop
# ═══════════════════════════════════════════════════════════════════════════════

run_iteration() {
    local iter_num=$1
    local iter_start=$(date +%s)
    local session_dir="$STATE_DIR/sessions/${STATE[session_id]}"
    local iter_log="$session_dir/iter_$(printf '%03d' $iter_num)"
    local before_commit
    before_commit=$(jj log -r @ --no-graph -T 'commit_id.shortest(12)' 2>/dev/null || echo "unknown")

    STATE[status]="running"
    session_save

    # Header
    echo ""
    echo -e "${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD}  ITERATION $iter_num${C_RESET}  ${C_DIM}$(date '+%H:%M:%S')${C_RESET}  ${C_DIM}commit:${C_RESET} $(vcs_commit_short)"
    echo -e "${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

    # Sync and show ready work
    beads_sync

    echo ""
    echo -e "  ${C_CYAN}${SYM_ARROW} Ready work${C_RESET}"
    local ready_count=$(beads_ready_count)

    if [[ -z "$ready_count" ]] || [[ "$ready_count" -eq 0 ]] 2>/dev/null; then
        echo -e "  ${C_DIM}No items ready${C_RESET}"

        if [[ "${CONFIG[auto_stop_empty]}" == true ]]; then
            log INFO "No more work available"
            return 2  # Signal to stop
        fi
    else
        echo -e "  ${C_GREEN}$ready_count${C_RESET} items:"
        beads_ready_items 3 | head -6
    fi

    # Interactive confirmation
    if [[ "${CONFIG[interactive]}" == true ]]; then
        echo ""
        read -rp "  ${C_YELLOW}Continue? [Y/n/s(kip)]${C_RESET} " response
        case "$response" in
            n|N) return 2 ;;
            s|S) return 0 ;;
        esac
    fi

    # Get prompt file
    local prompt_file
    if [[ "${CONFIG[mode]}" == "plan" ]]; then
        prompt_file="PROMPT_plan.md"
    else
        prompt_file="PROMPT_build.md"
    fi

    [[ ! -f "$prompt_file" ]] && { log ERROR "Prompt file not found: $prompt_file"; return 1; }

    # If --epic is set, prepend epic context to the prompt
    if [[ -n "${CONFIG[epic]}" ]]; then
        local epic_prompt_file=$(mktemp)
        {
            echo "## Epic Context"
            echo "You are working within epic \`${CONFIG[epic]}\`. Scope all task selection to this epic."
            echo "Use \`bd ready --json --limit 1 --type task --parent ${CONFIG[epic]}\` instead of the default bd ready call."
            echo "If no tasks are found, try \`bd ready --json --limit 1 --type bug --parent ${CONFIG[epic]}\`."
            echo ""
            cat "$prompt_file"
        } > "$epic_prompt_file"
        prompt_file="$epic_prompt_file"
    fi

    # Run Claude (with optional review-revision loop)
    local revision=0
    local max_revisions=${CONFIG[review_max_revisions]}
    local review_shipped=false
    local active_prompt_file="$prompt_file"

    while true; do
        revision=$((revision + 1))

        # Capture VCS state before Claude runs so we can detect changes
        local pre_claude_commit
        pre_claude_commit=$(jj log -r @ --no-graph -T 'commit_id.shortest(12)' 2>/dev/null || echo "unknown")

        [[ "${STATE[interrupted]}" == true ]] && break

        if [[ $revision -gt 1 ]]; then
            echo ""
            echo -e "  ${C_YELLOW}${SYM_ARROW} Revision $((revision - 1))/${max_revisions}${C_RESET} ${C_DIM}(incorporating review feedback)${C_RESET}"
        else
            echo ""
            echo -e "  ${C_CYAN}${SYM_ARROW} Running Claude${C_RESET} ${C_DIM}(${CONFIG[model]})${C_RESET}"
        fi

        if ! run_claude_with_retry "$active_prompt_file" "$iter_log"; then
            [[ "${STATE[interrupted]}" == true ]] && return 1
            STATE[consecutive_failures]=$((STATE[consecutive_failures] + 1))
            STATE[status]="failed"
            log_metric "status" "\"failed\""

            if [[ ${STATE[consecutive_failures]} -ge ${CONFIG[auto_stop_failures]} ]]; then
                log ERROR "${STATE[consecutive_failures]} consecutive failures"
                return 2
            fi

            return 1
        fi

        STATE[consecutive_failures]=0

        # Check if Claude actually changed anything (new commit or dirty worktree)
        local post_claude_commit
        post_claude_commit=$(jj log -r @ --no-graph -T 'commit_id.shortest(12)' 2>/dev/null || echo "unknown")
        local has_changes=false
        if [[ "$pre_claude_commit" != "$post_claude_commit" ]]; then
            has_changes=true
        elif vcs_is_dirty; then
            has_changes=true
        fi

        # Review phase
        if [[ "${CONFIG[review_enabled]}" == true ]]; then
            # Skip re-review if Claude made no changes (same diff = same verdict)
            if [[ $revision -gt 1 ]] && [[ "$has_changes" != true ]]; then
                log WARN "No new changes after revision, proceeding without re-review"
                break
            fi

            local review_result=0
            run_review "$iter_log" || review_result=$?

            case $review_result in
                0)  # SHIP
                    review_shipped=true
                    STATE[review_passes]=$(( ${STATE[review_passes]:-0} + 1 ))
                    break
                    ;;
                1)  # REVISE
                    STATE[review_revisions]=$(( ${STATE[review_revisions]:-0} + 1 ))
                    if [[ $((revision)) -ge $max_revisions ]]; then
                        log WARN "Max revisions ($max_revisions) reached, proceeding anyway"
                        break
                    fi
                    # Build a new prompt that includes the review feedback
                    local feedback_file="${iter_log}.review_feedback"
                    if [[ -f "$feedback_file" ]]; then
                        active_prompt_file=$(mktemp)
                        {
                            cat "$prompt_file"
                            echo ""
                            echo "## Review Feedback (revision $revision)"
                            echo "The previous attempt was reviewed and needs revision. Address this feedback:"
                            echo ""
                            cat "$feedback_file"
                        } > "$active_prompt_file"
                    fi
                    continue
                    ;;
                2)  # Parse failure
                    log WARN "Review parse failure, proceeding without review"
                    STATE[review_skipped]=$(( ${STATE[review_skipped]:-0} + 1 ))
                    break
                    ;;
                3)  # Fatal error (auth, connection, missing codex)
                    log ERROR "Review failed with fatal error - stopping loop"
                    log ERROR "Fix the issue and retry, or use --no-review to skip reviews"
                    return 2  # Signal stop to main loop
                    ;;
            esac
        else
            STATE[review_skipped]=$(( ${STATE[review_skipped]:-0} + 1 ))
            break
        fi
    done

    # Clean up temp prompt files if created
    [[ "$active_prompt_file" != "$prompt_file" ]] && [[ -f "$active_prompt_file" ]] && rm -f "$active_prompt_file"
    [[ -n "${CONFIG[epic]}" ]] && [[ -n "${epic_prompt_file:-}" ]] && [[ -f "${epic_prompt_file:-}" ]] && rm -f "$epic_prompt_file"

    local revisions_done=$((revision - 1))
    log_metric "revisions" "$revisions_done"

    # Parse metrics
    local metrics=$(parse_claude_metrics "$iter_log")
    local tokens=$(echo "$metrics" | cut -d'|' -f1)
    local cost=$(echo "$metrics" | cut -d'|' -f2)

    # Duration
    local iter_end=$(date +%s)
    local iter_duration=$((iter_end - iter_start))
    log_metric "duration" "$iter_duration"
    log_metric "status" "\"success\""

    # Results
    echo ""
    echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "  ${C_GREEN}${SYM_CHECK} Iteration $iter_num complete${C_RESET}"
    printf "  ${C_DIM}Duration:${C_RESET} %-12s" "$(format_duration $iter_duration)"
    printf "${C_DIM}Tokens:${C_RESET} %-10s" "$(format_number $tokens)"
    printf "${C_DIM}Cost:${C_RESET} \$%s\n" "$cost"
    if [[ "${CONFIG[review_enabled]}" == true ]]; then
        if [[ "$review_shipped" == true ]]; then
            printf "  ${C_DIM}Review:${C_RESET} ${C_GREEN}SHIP${C_RESET}"
        else
            printf "  ${C_DIM}Review:${C_RESET} ${C_YELLOW}max revisions reached${C_RESET}"
        fi
        [[ $revisions_done -gt 0 ]] && printf " ${C_DIM}(%d revision(s))${C_RESET}" "$revisions_done"
        echo ""
    fi

    # Git changes
    vcs_changes_summary "$before_commit"

    # Sync and push
    beads_sync
    vcs_push

    # Checkpoint
    if [[ $((iter_num % CONFIG[checkpoint_interval])) -eq 0 ]]; then
        session_save
    fi

    # Webhook
    send_webhook "iteration_complete" "{\"iteration\":$iter_num,\"duration\":$iter_duration,\"tokens\":$tokens}"

    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Reports
# ═══════════════════════════════════════════════════════════════════════════════

generate_report() {
    local session_id="${1:-${STATE[session_id]}}"
    local session_dir="$STATE_DIR/sessions/$session_id"
    local report_file="$session_dir/report.md"

    [[ ! -d "$session_dir" ]] && { log ERROR "Session not found: $session_id"; return 1; }

    local state_file="$session_dir/state.json"
    local metrics_file="$session_dir/metrics.jsonl"

    cat > "$report_file" <<EOF
# Beads Loop Report

**Session:** $session_id
**Generated:** $(date -Iseconds)

## Summary

| Metric | Value |
|--------|-------|
| Iterations | $(jq -r '.iteration' "$state_file") |
| Status | $(jq -r '.status' "$state_file") |
| Total Tokens | $(format_number $(jq -r '.total_tokens' "$state_file")) |
| Total Cost | \$$(jq -r '.total_cost' "$state_file") |
| Duration | $(format_duration $(($(date +%s) - $(jq -r '.start_time' "$state_file")))) |
| Model | $(jq -r '.config.model' "$state_file") |
| Bookmark | $(jq -r '.vcs.bookmark' "$state_file") |
| Review Enabled | $(jq -r '.review.enabled // "N/A"' "$state_file") |
| Review Model | $(jq -r '.review.model // "N/A"' "$state_file") |
| Review Passes | $(jq -r '.review.passes // 0' "$state_file") |
| Review Revisions | $(jq -r '.review.revisions // 0' "$state_file") |
| Review Skipped | $(jq -r '.review.skipped // 0' "$state_file") |

## Metrics Over Time

EOF

    # Add metrics chart (simplified ASCII version)
    if [[ -f "$metrics_file" ]]; then
        echo '```' >> "$report_file"
        echo "Tokens per iteration:" >> "$report_file"
        jq -r 'select(.metric=="tokens_input" or .metric=="tokens_output") | "\(.iteration): \(.value)"' "$metrics_file" >> "$report_file"
        echo '```' >> "$report_file"
    fi

    log SUCCESS "Report generated: $report_file"
    echo "$report_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Signal Handlers
# ═══════════════════════════════════════════════════════════════════════════════

handle_interrupt() {
    if [[ "${STATE[interrupted]}" == true ]]; then
        echo ""
        echo -e "${C_RED}Force quit${C_RESET}"
        # Reset trap and re-raise to get proper exit code
        trap - INT TERM EXIT
        kill -INT $$
    fi
    echo ""
    log WARN "Interrupted - finishing gracefully... (Ctrl+C again to force quit)"
    STATE[interrupted]=true
    STATE[status]="interrupted"
}

handle_pause() {
    if [[ "${STATE[paused]}" == true ]]; then
        STATE[paused]=false
        STATE[status]="running"
        log INFO "Resumed"
    else
        STATE[paused]=true
        STATE[status]="paused"
        log WARN "Paused (SIGUSR1 to resume)"
    fi
}

cleanup() {
    local exit_code=$?

    spinner_stop
    cursor_show

    [[ "${STATE[status]}" == "running" ]] && STATE[status]="complete"
    session_save

    # Summary
    if [[ ${STATE[iteration]} -gt 0 ]]; then
        echo ""
        echo -e "${C_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "${C_BOLD}  SESSION COMPLETE${C_RESET}"
        echo -e "${C_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo ""

        local total_duration=$(($(date +%s) - STATE[start_time]))

        printf "  ${C_DIM}%-14s${C_RESET} %s\n" "Iterations:" "${STATE[iteration]}"
        printf "  ${C_DIM}%-14s${C_RESET} %s\n" "Duration:" "$(format_duration $total_duration)"
        printf "  ${C_DIM}%-14s${C_RESET} %s\n" "Tokens:" "$(format_number ${STATE[total_tokens]})"
        printf "  ${C_DIM}%-14s${C_RESET} \$%s\n" "Cost:" "${STATE[total_cost]}"
        printf "  ${C_DIM}%-14s${C_RESET} %s\n" "Status:" "${STATE[status]}"
        if [[ "${CONFIG[review_enabled]}" == true ]]; then
            printf "  ${C_DIM}%-14s${C_RESET} %s (model: %s)\n" "Review:" "${C_GREEN}${STATE[review_passes]} shipped${C_RESET}, ${C_YELLOW}${STATE[review_revisions]} revised${C_RESET}, ${C_GRAY}${STATE[review_skipped]} skipped${C_RESET}" "${CONFIG[review_model]}"
        fi
        echo ""
        printf "  ${C_DIM}Session:${C_RESET} %s\n" "${STATE[session_id]}"
        printf "  ${C_DIM}Logs:${C_RESET} %s\n" "$STATE_DIR/sessions/${STATE[session_id]}"
        echo ""

        # Beads stats
        echo -e "  ${C_DIM}Beads:${C_RESET}"
        beads_stats | sed 's/^/    /'
        echo ""

        notify "Loop Complete" "${STATE[iteration]} iterations, \$${STATE[total_cost]}"
        send_webhook "session_complete" "{\"iterations\":${STATE[iteration]},\"cost\":${STATE[total_cost]}}"
    fi

    # Record in history
    echo "{\"ts\":$(date +%s),\"session\":\"${STATE[session_id]}\",\"iterations\":${STATE[iteration]},\"status\":\"${STATE[status]}\",\"review\":{\"passes\":${STATE[review_passes]},\"revisions\":${STATE[review_revisions]},\"skipped\":${STATE[review_skipped]}}}" >> "$HISTORY_FILE"

    exit $exit_code
}

# ═══════════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════════

load_config() {
    # Load from TOML if exists
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" ]] || [[ "$key" == \#* ]] && continue
            key=$(echo "$key" | tr -d ' ')
            value=$(echo "$value" | tr -d ' "'"'"'')
            [[ -n "${CONFIG[$key]+x}" ]] && CONFIG[$key]="$value"
        done < "$CONFIG_FILE"
    fi
}

show_help() {
    cat <<EOF
${C_BOLD}beads-loop${C_RESET} v$VERSION - Production-grade loop runner for Claude Code

${C_BOLD}USAGE${C_RESET}
    $SCRIPT_NAME [command] [options]

${C_BOLD}COMMANDS${C_RESET}
    run [mode]          Run the loop (default command)
    resume [session]    Resume a previous session
    list                List recent sessions
    report [session]    Generate session report
    status              Show current/latest session status

${C_BOLD}MODES${C_RESET}
    build               Use PROMPT_build.md (default)
    plan                Use PROMPT_plan.md (default: 3 iterations)

${C_BOLD}OPTIONS${C_RESET}
    -n, --max N         Maximum iterations (0 = unlimited)
    -m, --model MODEL   Claude model (default: opus)
    -d, --delay N       Delay between iterations (default: 3s)
    -i, --interactive   Confirm before each iteration
    --no-push           Don't push to remote
    --no-notify         Disable notifications
    --sound             Enable sound notifications
    --webhook URL       Send events to webhook URL
    --epic ID           Scope work to children of a specific epic
    --no-review         Disable review phase after each iteration
    --review-model M    Review model for codex exec (default: gpt-5.2-codex)
    --review-max-revisions N
                        Max revision attempts on REVISE (default: 3)
    -v, --verbose       Verbose output
    -h, --help          Show this help

${C_BOLD}REVIEW${C_RESET}
    After each work iteration, a review model evaluates changes via
    codex exec. The reviewer reads the jj diff and task spec, then
    outputs SHIP or REVISE. On REVISE, the worker re-runs with
    feedback (up to --review-max-revisions times). On SHIP, the
    loop proceeds normally.

    Review prompt: PROMPT_review.md
    State files:   iter_NNN.review, iter_NNN.review_feedback

${C_BOLD}SIGNALS${C_RESET}
    Ctrl+C              Stop gracefully
    SIGUSR1             Pause/resume

${C_BOLD}EXAMPLES${C_RESET}
    $SCRIPT_NAME                          # Build mode, unlimited
    $SCRIPT_NAME plan                     # Plan mode, 3 iterations
    $SCRIPT_NAME run build -n 10          # Build, max 10 iterations
    $SCRIPT_NAME run -i --no-push         # Interactive, no push
    $SCRIPT_NAME --epic about-291          # Scope to epic's children
    $SCRIPT_NAME resume                   # Resume latest session
    $SCRIPT_NAME report                   # Generate report

${C_BOLD}CONFIG${C_RESET}
    Create .ralph/config.toml:

        max_iterations = 10
        model = "sonnet"
        delay = 5
        push_enabled = false
        webhook_url = "https://..."

EOF
}

parse_args() {
    local command=""
    local positional=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            run|resume|list|report|status)
                command="$1"
                shift ;;
            plan|build)
                CONFIG[mode]="$1"
                [[ "$1" == "plan" ]] && [[ ${CONFIG[max_iterations]} -eq 0 ]] && CONFIG[max_iterations]=3
                shift ;;
            -n|--max)
                CONFIG[max_iterations]="$2"
                shift 2 ;;
            -m|--model)
                CONFIG[model]="$2"
                shift 2 ;;
            -d|--delay)
                CONFIG[delay]="$2"
                shift 2 ;;
            -i|--interactive)
                CONFIG[interactive]=true
                shift ;;
            --no-push)
                CONFIG[push_enabled]=false
                shift ;;
            --no-notify)
                CONFIG[notifications]=false
                shift ;;
            --sound)
                CONFIG[sound]=true
                shift ;;
            --epic)
                CONFIG[epic]="$2"
                shift 2 ;;
            --no-review)
                CONFIG[review_enabled]=false
                shift ;;
            --review-model)
                CONFIG[review_model]="$2"
                shift 2 ;;
            --review-max-revisions)
                CONFIG[review_max_revisions]="$2"
                shift 2 ;;
            --webhook)
                CONFIG[webhook_url]="$2"
                shift 2 ;;
            -v|--verbose)
                CONFIG[verbose]=true
                shift ;;
            -h|--help)
                show_help
                exit 0 ;;
            -*)
                log ERROR "Unknown option: $1"
                exit 1 ;;
            *)
                positional+=("$1")
                shift ;;
        esac
    done

    # Handle command
    case "${command:-run}" in
        list)
            session_list
            exit 0 ;;
        report)
            generate_report "${positional[0]:-}"
            exit 0 ;;
        status)
            [[ -L "$STATE_DIR/latest" ]] && cat "$STATE_DIR/latest/state.json" | jq .
            exit 0 ;;
        resume)
            local sid="${positional[0]:-}"
            if [[ -z "$sid" ]] && [[ -L "$STATE_DIR/latest" ]]; then
                sid=$(basename "$(readlink "$STATE_DIR/latest")")
            fi
            if session_load "$sid"; then
                log INFO "Resuming session: $sid"
            else
                log ERROR "Cannot resume session: $sid"
                exit 1
            fi
            ;;
        run)
            session_new
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    setup_terminal
    setup_symbols

    mkdir -p "$STATE_DIR"

    load_config
    parse_args "$@"

    # Traps
    trap cleanup EXIT
    trap handle_interrupt INT TERM
    trap handle_pause USR1

    # Validation
    beads_check || exit 1

    local prompt_file="PROMPT_${CONFIG[mode]}.md"
    [[ ! -f "$prompt_file" ]] && { log ERROR "Prompt file not found: $prompt_file"; exit 1; }

    init_logging

    # Header
    draw_header
    echo ""
    printf "  ${C_DIM}%-12s${C_RESET} ${C_BOLD}%s${C_RESET}\n" "Mode:" "${CONFIG[mode]}"
    printf "  ${C_DIM}%-12s${C_RESET} %s\n" "Model:" "${CONFIG[model]}"
    printf "  ${C_DIM}%-12s${C_RESET} %s\n" "Bookmark:" "$(vcs_branch)"
    printf "  ${C_DIM}%-12s${C_RESET} %s\n" "Max:" "${CONFIG[max_iterations]:-∞}"
    [[ -n "${CONFIG[epic]}" ]] && printf "  ${C_DIM}%-12s${C_RESET} %s\n" "Epic:" "${CONFIG[epic]}"
    if [[ "${CONFIG[review_enabled]}" == true ]]; then
        printf "  ${C_DIM}%-12s${C_RESET} %s ${C_DIM}(max %s revisions)${C_RESET}\n" "Review:" "${CONFIG[review_model]}" "${CONFIG[review_max_revisions]}"
    else
        printf "  ${C_DIM}%-12s${C_RESET} disabled\n" "Review:"
    fi
    printf "  ${C_DIM}%-12s${C_RESET} %s\n" "Session:" "${STATE[session_id]}"

    send_webhook "session_start" "{\"mode\":\"${CONFIG[mode]}\"}"

    # Main loop
    while true; do
        [[ "${STATE[interrupted]}" == true ]] && break

        # Pause handling
        while [[ "${STATE[paused]}" == true ]] && [[ "${STATE[interrupted]}" != true ]]; do
            sleep 1 || true
        done

        # Max iterations check
        if [[ ${CONFIG[max_iterations]} -gt 0 ]] && [[ ${STATE[iteration]} -ge ${CONFIG[max_iterations]} ]]; then
            log SUCCESS "Completed ${CONFIG[max_iterations]} iterations"
            break
        fi

        STATE[iteration]=$((STATE[iteration] + 1))

        local result=0
        run_iteration ${STATE[iteration]} || result=$?

        case $result in
            0) ;;  # Success
            1) log WARN "Iteration failed, continuing..." ;;
            2) break ;;  # Stop signal
        esac

        [[ "${STATE[interrupted]}" == true ]] && break

        # Delay
        if [[ ${CONFIG[max_iterations]} -eq 0 ]] || [[ ${STATE[iteration]} -lt ${CONFIG[max_iterations]} ]]; then
            echo ""
            echo -e "  ${C_DIM}Next in ${CONFIG[delay]}s... (Ctrl+C to stop)${C_RESET}"
            sleep "${CONFIG[delay]}" || true
            [[ "${STATE[interrupted]}" == true ]] && break
        fi
    done

    STATE[status]="complete"
}

main "$@"
