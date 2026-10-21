#!/usr/bin/env bash
# ExecStartPre steps for one dsv41 cluster rank. Subcommand is $1.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
dsv41_source_cluster

cmd=${1:-}
fabric_wait=${DSV41_FABRIC_WAIT_SEC:-120}
master_wait=${DSV41_MASTER_WAIT_SEC:-180}

wait_until() {
  local seconds=$1
  local deadline=$((SECONDS + seconds))
  shift
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      return 1
    fi
    sleep 2
  done
}

fabric_up() {
  local ip_bin
  ip_bin=$(dsv41_ip)
  "$ip_bin" -4 addr show "$DSV41_FAB_IF" | grep -qF "${DSV41_HOST_IP}/"
}

master_up() {
  ping -c 1 -W 1 "$DSV41_MASTER_ADDR" >/dev/null 2>&1
}

case "$cmd" in
  wait-fabric)
    if ! wait_until "$fabric_wait" fabric_up; then
      dsv41_die "${DSV41_HOST_IP} did not appear on ${DSV41_FAB_IF} within ${fabric_wait}s"
    fi
    ;;
  wait-master)
    if [ "$DSV41_ROLE" != worker ]; then
      exit 0
    fi
    if ! wait_until "$master_wait" master_up; then
      dsv41_die "head ${DSV41_MASTER_ADDR} did not answer ping within ${master_wait}s"
    fi
    ;;
  preflight)
    if [ ! -d "$DSV41_MODEL_DIR" ]; then
      dsv41_die "model directory missing: ${DSV41_MODEL_DIR}"
    fi
    if ! "$(dsv41_docker)" image inspect "$DSV41_IMAGE" >/dev/null 2>&1; then
      dsv41_die "image not present locally (--pull=never): ${DSV41_IMAGE}"
    fi
    if [ "$DSV41_ROLE" = head ]; then
      unit=""
      for unit in spark-vllm.service nvpair.service; do
        if "$(dsv41_systemctl)" is-active --quiet "$unit"; then
          dsv41_die "${unit} is active. Stop and disable it before starting the cluster (GB10 unified memory). A user unit cannot stop a system unit."
        fi
      done
    fi
    install -d -m 755 "${HOME:?}/${DSV41_CACHE_REL}"
    install -d -m 755 "${HOME}/.config/dsv41"
    ;;
  docker-rm)
    "$(dsv41_docker)" rm -f "$DSV41_CONTAINER" >/dev/null 2>&1 || true
    if [ "$DSV41_ROLE" = head ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
      rm -f "$(dsv41_ready_flag)"
    fi
    ;;
  drop-caches)
    # GB10 CUDA allocations do not reclaim page cache. sudoers is NOPASSWD.
    if ! /usr/bin/sudo -n /bin/sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'; then
      dsv41_die "drop_caches needs passwordless sudo (sudo -n). See docs/dgx-spark.md"
    fi
    ;;
  api-key)
    exec "$here/api-key.sh" write-env
    ;;
  *)
    dsv41_die "usage: prepare.sh wait-fabric|wait-master|preflight|docker-rm|drop-caches|api-key"
    ;;
esac
