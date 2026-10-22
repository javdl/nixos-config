#!/usr/bin/env bash
# Watchdog for the dsv41 head.
#
# Skip while dsv41-cluster-ready has not succeeded, and for one startup
# grace after it has, so the cold load is not a strike.
#
# Two signals restart the head:
# - The spark2 TCPStore source port changes, or the connection drops, on
#   N consecutive ticks. The head listens dual-stack, so that socket is an
#   IPv4 row in /proc/net/tcp or an IPv4-mapped row in /proc/net/tcp6. A
#   worker-container restart looks like this while /health is still 200.
#   Those ticks do not wait on a chat call.
# - An authenticated 1-token chat (max_tokens 1) fails N times while the
#   engine is idle or its token counters are frozen. A timeout where
#   /metrics shows num_requests_running > 0 and prompt or generation
#   tokens advanced since the previous scrape is a live prefill, not a
#   strike. The curl timeout is short. The timer interval is shorter than
#   that timeout, so a hung probe is followed immediately by the next one.
#
# The API key is read the same way as the other units. It is never printed.
set -euo pipefail
set +x

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
dsv41_source_cluster
dsv41_require_runtime

unit=dsv41-cluster-head
state=$(dsv41_health_fail_file)
peer_file=$(dsv41_health_peer_file)
failures=${DSV41_HEALTH_FAILURES:-5}
timeout=${DSV41_HEALTH_TIMEOUT_SEC:-20}
grace=${DSV41_HEALTH_GRACE_SEC:-60}
peer_confirms=${DSV41_HEALTH_PEER_CONFIRMS:-2}

case "$failures" in
  ''|*[!0-9]*) failures=5 ;;
esac
case "$timeout" in
  ''|*[!0-9]*) timeout=20 ;;
esac
case "$grace" in
  ''|*[!0-9]*) grace=60 ;;
esac
case "$peer_confirms" in
  ''|*[!0-9]*) peer_confirms=2 ;;
esac

restart_head() {
  printf '%s\n' 0 >"$state"
  rm -f "$peer_file" "$(dsv41_health_metrics_file)"
  "$(dsv41_systemctl)" --user restart --no-block "$unit"
}

note_failure() {
  local n
  n=$(cat "$state" 2>/dev/null || echo 0)
  case "$n" in
    ''|*[!0-9]*) n=0 ;;
  esac
  n=$((n + 1))
  printf '%s\n' "$n" >"$state"
  if [ "$n" -ge "$failures" ]; then
    echo "dsv41 cluster: ${n} failed probes; restarting ${unit}" >&2
    restart_head
  fi
}

# Little-endian hex, the form /proc/net/tcp uses. Empty or invalid input
# fails the caller so a bad address cannot look like "worker down".
dsv41_ipv4_le_hex() {
  local ip=$1 a b c d
  case "$ip" in
    *.*.*.*) ;;
    *) return 1 ;;
  esac
  IFS=. read -r a b c d <<EOF
$ip
EOF
  a=$((10#$a))
  b=$((10#$b))
  c=$((10#$c))
  d=$((10#$d))
  if [ "$a" -gt 255 ] || [ "$b" -gt 255 ] || [ "$c" -gt 255 ] || [ "$d" -gt 255 ]; then
    return 1
  fi
  printf '%02X%02X%02X%02X' "$d" "$c" "$b" "$a"
}

# Source ports of established sockets on local_port whose remote address
# is remote_hex. Unreadable tables contribute nothing.
dsv41_tcp_established_ports() {
  local table=$1 remote_hex=$2 port_hex=$3
  [ -r "$table" ] || return 0
  awk -v remote_hex="$remote_hex" -v port="$port_hex" '
    NR == 1 { next }
    {
      split(toupper($2), local, ":")
      split(toupper($3), remote, ":")
      if (local[2] != port) next
      if (remote[1] != remote_hex) next
      if (toupper($4) != "01") next
      print remote[2]
    }
  ' "$table"
}

# Established TCPStore client ports on the worker, comma-separated.
# The head listens dual-stack, so spark2's IPv4 connection is in
# /proc/net/tcp6 as 0000000000000000FFFF0000 plus the little-endian IPv4,
# not in /proc/net/tcp. Both tables are read. Prints "down" when at least
# one table is readable and no matching socket exists. Returns 1 when
# neither table is readable, or the worker address is unusable, so the
# caller leaves the saved baseline alone.
dsv41_worker_tcpstore_identity() {
  local tcp4=${DSV41_PROC_NET_TCP:-/proc/net/tcp}
  local tcp6=${DSV41_PROC_NET_TCP6:-/proc/net/tcp6}
  local worker_hex port_hex mapped ports
  worker_hex=$(dsv41_ipv4_le_hex "${DSV41_WORKER_IP:-}") || return 1
  case "${DSV41_MASTER_PORT:-}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  if [ ! -r "$tcp4" ] && [ ! -r "$tcp6" ]; then
    return 1
  fi
  port_hex=$(printf '%04X' "$DSV41_MASTER_PORT")
  mapped="0000000000000000FFFF0000${worker_hex}"
  ports=$(
    {
      dsv41_tcp_established_ports "$tcp4" "$worker_hex" "$port_hex"
      dsv41_tcp_established_ports "$tcp6" "$mapped" "$port_hex"
    } | sort -u | paste -sd, -
  )
  if [ -z "$ports" ]; then
    printf '%s\n' down
  else
    printf '%s\n' "$ports"
  fi
}

# True when any saved source port is still established. An extra NCCL
# socket on the same master port is not a worker restart.
dsv41_ports_overlap() {
  local saved=$1 current=$2 p
  [ "$saved" = down ] && return 1
  [ "$current" = down ] && return 1
  [ -z "$saved" ] || [ -z "$current" ] && return 1
  local IFS=,
  for p in $saved; do
    case ",${current}," in
      *",${p},"*) return 0 ;;
    esac
  done
  return 1
}

peer_read() {
  peer_id=
  peer_streak=0
  [ -f "$peer_file" ] || return 0
  peer_id=$(sed -n '1s/^id=//p' "$peer_file")
  peer_streak=$(sed -n '2s/^streak=//p' "$peer_file")
  case "$peer_streak" in
    ''|*[!0-9]*) peer_streak=0 ;;
  esac
}

peer_write() {
  printf 'id=%s\nstreak=%s\n' "$1" "$2" >"$peer_file"
}

# Restart when the worker's TCPStore identity has been gone for N ticks.
# A single sample can be a parse glitch or a socket that has not finished
# closing. Returns 0 when the caller should continue with the chat probe.
observe_peer() {
  local current saved
  if ! current=$(dsv41_worker_tcpstore_identity); then
    return 0
  fi
  peer_read
  saved=$peer_id
  if [ -z "$saved" ]; then
    return 0
  fi
  if dsv41_ports_overlap "$saved" "$current"; then
    peer_write "$saved" 0
    return 0
  fi
  peer_streak=$((peer_streak + 1))
  peer_write "$saved" "$peer_streak"
  if [ "$peer_streak" -ge "$peer_confirms" ]; then
    echo "dsv41 cluster: worker ${DSV41_WORKER_IP} TCPStore peer changed (${saved} -> ${current}) on ${peer_streak} ticks; restarting ${unit}" >&2
    restart_head
    exit 0
  fi
  echo "dsv41 cluster: worker ${DSV41_WORKER_IP} TCPStore peer changed (${saved} -> ${current}); confirming ${peer_streak}/${peer_confirms}" >&2
  exit 0
}

arm_peer_baseline() {
  local current saved
  if ! current=$(dsv41_worker_tcpstore_identity); then
    return 0
  fi
  case "$current" in
    down | "") ;;
    *)
      peer_write "$current" 0
      return 0
      ;;
  esac
  peer_read
  saved=$peer_id
  if [ -n "$saved" ]; then
    peer_write "$saved" 0
  fi
}

dsv41_metrics_read() {
  metrics_prompt=
  metrics_generation=
  metrics_known=0
  local f line_p line_g
  f=$(dsv41_health_metrics_file)
  [ -f "$f" ] || return 0
  line_p=$(sed -n 's/^prompt=//p' "$f")
  line_g=$(sed -n 's/^generation=//p' "$f")
  case "$line_p" in
    ''|*[!0-9]*) return 0 ;;
  esac
  case "$line_g" in
    ''|*[!0-9]*) return 0 ;;
  esac
  metrics_prompt=$line_p
  metrics_generation=$line_g
  metrics_known=1
}

dsv41_metrics_write() {
  printf 'prompt=%s\ngeneration=%s\n' "$1" "$2" >"$(dsv41_health_metrics_file)"
}

# Sum Prometheus series. Names match with or without a vllm: prefix, and
# with or without labels. Histogram buckets and *_created are not the
# counters. Prints "running prompt generation". Returns 1 when the
# running gauge is absent.
dsv41_parse_metrics() {
  awk '
    function metric_name(s) {
      sub(/\{.*/, "", s)
      sub(/^vllm:/, "", s)
      return s
    }
    /^#/ || NF < 2 { next }
    {
      name = metric_name($1)
      value = $2 + 0
      if (name == "num_requests_running") {
        running += value
        seen_running = 1
      } else if (name == "prompt_tokens_total") {
        prompt += value
      } else if (name == "generation_tokens_total") {
        generation += value
      }
    }
    END {
      if (!seen_running) exit 1
      printf "%d %d %d\n", running, prompt, generation
    }
  ' "$1"
}

# A chat failure is not a strike when a request is in flight and the
# engine's token counters moved. The first busy scrape only records the
# baseline, so a frozen engine still reaches N strikes one probe later.
# Returns 0 when the caller should not count this probe.
dsv41_chat_failure_is_live() {
  local metrics_url code parsed running prompt generation advanced
  metrics_url="http://127.0.0.1:${DSV41_PORT}/metrics"
  code=$(
    "$(dsv41_curl)" --config "$cfg" \
      --connect-timeout 5 --max-time 5 -s -o "$metrics_body" -w '%{http_code}' \
      "$metrics_url" || true
  )
  if [ "$code" != 200 ]; then
    return 1
  fi
  if ! parsed=$(dsv41_parse_metrics "$metrics_body"); then
    return 1
  fi
  read -r running prompt generation <<EOF
$parsed
EOF
  case "$running" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$prompt" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$generation" in
    ''|*[!0-9]*) return 1 ;;
  esac
  dsv41_metrics_read
  if [ "$metrics_known" -eq 1 ]; then
    if [ "$prompt" -lt "$metrics_prompt" ] || [ "$generation" -lt "$metrics_generation" ]; then
      dsv41_metrics_write "$prompt" "$generation"
      echo "dsv41 cluster: token counters went backwards; recording a new baseline" >&2
      return 0
    fi
    advanced=0
    if [ "$prompt" -gt "$metrics_prompt" ] || [ "$generation" -gt "$metrics_generation" ]; then
      advanced=1
    fi
    if [ "$running" -gt 0 ] && [ "$advanced" -eq 1 ]; then
      dsv41_metrics_write "$prompt" "$generation"
      printf '%s\n' 0 >"$state"
      echo "dsv41 cluster: chat probe failed but a request is running and token counters advanced; not a strike" >&2
      return 0
    fi
  elif [ "$running" -gt 0 ]; then
    dsv41_metrics_write "$prompt" "$generation"
    printf '%s\n' 0 >"$state"
    echo "dsv41 cluster: chat probe failed with a request running; recording the token baseline" >&2
    return 0
  fi
  dsv41_metrics_write "$prompt" "$generation"
  return 1
}

if ! "$(dsv41_systemctl)" --user is-active --quiet "$unit"; then
  exit 0
fi

ready_flag=$(dsv41_ready_flag)
health_url="http://127.0.0.1:${DSV41_PORT}/health"
if [ ! -f "$ready_flag" ]; then
  dsv41_clear_health_state
  if ! "$(dsv41_curl)" --connect-timeout 5 --max-time 10 -sf -o /dev/null "$health_url"; then
    echo "dsv41 cluster: /health is not up yet; skipping the chat probe" >&2
  else
    echo "dsv41 cluster: /health is up; chat probe waits for dsv41-cluster-ready" >&2
  fi
  exit 0
fi

ready_age=$(($(date +%s) - $(stat -c %Y "$ready_flag")))
if [ "$ready_age" -ge 0 ] && [ "$ready_age" -lt "$grace" ]; then
  dsv41_clear_health_state
  echo "dsv41 cluster: ready flag is ${ready_age}s old; skipping probes during the ${grace}s startup grace" >&2
  exit 0
fi

observe_peer

if ! "$(dsv41_curl)" --connect-timeout 5 --max-time 10 -sf -o /dev/null "$health_url"; then
  note_failure
  exit 0
fi

url="http://127.0.0.1:${DSV41_PORT}/v1/chat/completions"
body=$(printf '{"model":"%s","messages":[{"role":"user","content":"ping"}],"max_tokens":1}' "$DSV41_SERVED")
cfg=$(mktemp "${XDG_RUNTIME_DIR}/dsv41-curl.XXXXXX")
body_file=$(mktemp "${XDG_RUNTIME_DIR}/dsv41-body.XXXXXX")
metrics_body=$(mktemp "${XDG_RUNTIME_DIR}/dsv41-metrics.XXXXXX")
chmod 600 "$cfg" "$body_file" "$metrics_body"
trap 'rm -f "$cfg" "$body_file" "$metrics_body"' EXIT
printf '%s' "$body" >"$body_file"
printf 'header = "Content-Type: application/json"\n' >>"$cfg"

# bash rather than the shebang so a caller with bash on PATH can run this
# where /usr/bin/env is absent (the flake check sandbox).
if ! bash "$here/api-key.sh" append-auth "$cfg"; then
  note_failure
  exit 0
fi

code=$(
  "$(dsv41_curl)" --config "$cfg" --data-binary "@${body_file}" \
    --connect-timeout 5 --max-time "$timeout" -s -o /dev/null -w '%{http_code}' \
    "$url" || true
)
if [ "$code" = 200 ]; then
  printf '%s\n' 0 >"$state"
  arm_peer_baseline
  exit 0
fi
if [ "$code" = 401 ]; then
  echo "dsv41 cluster: chat probe returned 401. The API key was rejected. ~/.config/spark-vllm/api.env must be the Aperture provider key. Fix the file, then: systemctl --user restart dsv41-cluster-head" >&2
  exit 1
fi

if dsv41_chat_failure_is_live; then
  exit 0
fi

note_failure
exit 0
