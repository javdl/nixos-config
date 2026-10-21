#!/usr/bin/env bash
# One 1-token chat probe against 127.0.0.1. The timer runs this every 2 min.
# Two consecutive failures restart the head. Probes while the head unit is
# not active (model load, restart) are ignored so a 6 minute boot is not a
# failure. /health needs no key; this chat probe does.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
dsv41_source_cluster
dsv41_require_runtime

unit=dsv41-cluster-head
state="${XDG_RUNTIME_DIR}/dsv41-cluster-health.fails"
failures=${DSV41_HEALTH_FAILURES:-2}
timeout=${DSV41_HEALTH_TIMEOUT_SEC:-90}

if ! "$(dsv41_systemctl)" --user is-active --quiet "$unit"; then
  exit 0
fi

note_failure() {
  local n
  n=$(cat "$state" 2>/dev/null || echo 0)
  case "$n" in
    ''|*[!0-9]*) n=0 ;;
  esac
  n=$((n + 1))
  printf '%s\n' "$n" >"$state"
  if [ "$n" -ge "$failures" ]; then
    echo "dsv41 cluster: ${n} failed 1-token probes; restarting ${unit}" >&2
    printf '%s\n' 0 >"$state"
    "$(dsv41_systemctl)" --user restart --no-block "$unit"
  fi
}

url="http://127.0.0.1:${DSV41_PORT}/v1/chat/completions"
body=$(printf '{"model":"%s","messages":[{"role":"user","content":"ping"}],"max_tokens":1}' "$DSV41_SERVED")
cfg=$(mktemp "${XDG_RUNTIME_DIR}/dsv41-curl.XXXXXX")
body_file=$(mktemp "${XDG_RUNTIME_DIR}/dsv41-body.XXXXXX")
chmod 600 "$cfg" "$body_file"
trap 'rm -f "$cfg" "$body_file"' EXIT
printf '%s' "$body" >"$body_file"
printf 'header = "Content-Type: application/json"\n' >>"$cfg"

if ! "$here/api-key.sh" append-auth "$cfg"; then
  note_failure
  exit 0
fi

if "$(dsv41_curl)" --config "$cfg" --data-binary "@${body_file}" --max-time "$timeout" -sf -o /dev/null "$url"; then
  printf '%s\n' 0 >"$state"
  exit 0
fi

note_failure
exit 0
