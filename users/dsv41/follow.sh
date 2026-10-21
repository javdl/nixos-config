#!/usr/bin/env bash
# On the worker, restart this rank only when the head goes from up to down.
# Aperture binds HTTP on 127.0.0.1, which spark2 cannot reach, so the default
# watch is a connect/close on the CX7 TCPStore (master addr/port). That is
# the same rendezvous the ranks already use; it does not follow DSV41_BIND.
# open exposure watches http://<head-cx7>:<port>/health instead (no API key).
# The first sample only records state, so a normal head load is not a restart.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
dsv41_source_cluster
dsv41_require_runtime

state="${XDG_RUNTIME_DIR}/dsv41-cluster-follow.state"
prev=unknown
if [ -f "$state" ]; then
  prev=$(cat "$state")
fi

case "$DSV41_MASTER_ADDR" in
  *.*.*.*) ;;
  *) dsv41_die "refusing to probe unexpected master address" ;;
esac
case "$DSV41_MASTER_PORT" in
  ''|*[!0-9]*) dsv41_die "refusing to probe unexpected master port" ;;
esac

up=0
if [ "$DSV41_FOLLOW_MODE" = tcp ]; then
  if /usr/bin/timeout 5 /bin/bash -c ':</dev/tcp/$1/$2' _ "$DSV41_MASTER_ADDR" "$DSV41_MASTER_PORT" 2>/dev/null; then
    up=1
  fi
elif [ "$DSV41_FOLLOW_MODE" = http ]; then
  if "$(dsv41_curl)" -sf --max-time 5 -o /dev/null "http://${DSV41_MASTER_ADDR}:${DSV41_PORT}/health"; then
    up=1
  fi
else
  dsv41_die "unknown follow mode: ${DSV41_FOLLOW_MODE}"
fi

if [ "$up" = 1 ]; then
  now=up
else
  now=down
fi
printf '%s\n' "$now" >"$state"

if [ "$prev" = up ] && [ "$now" = down ]; then
  echo "dsv41 cluster: head went down; restarting dsv41-cluster-worker" >&2
  "$(dsv41_systemctl)" --user restart --no-block dsv41-cluster-worker
fi
