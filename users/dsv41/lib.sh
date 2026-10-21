#!/usr/bin/env bash
# Shared helpers for the dsv41 cluster user units. No secrets.
set -euo pipefail

dsv41_die() {
  echo "dsv41 cluster: $*" >&2
  exit 1
}

dsv41_source_cluster() {
  if [ -z "${DSV41_CLUSTER_ENV:-}" ]; then
    dsv41_die "DSV41_CLUSTER_ENV is unset"
  fi
  set -a
  # shellcheck disable=SC1090
  . "$DSV41_CLUSTER_ENV"
  set +a
}

dsv41_require_runtime() {
  if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "$XDG_RUNTIME_DIR" ]; then
    dsv41_die "XDG_RUNTIME_DIR is unset; this script must run as a systemd user unit"
  fi
}

dsv41_ip() {
  if [ -n "${DSV41_IP_BIN:-}" ]; then
    printf '%s\n' "$DSV41_IP_BIN"
    return
  fi
  local c
  for c in /usr/sbin/ip /sbin/ip /usr/bin/ip; do
    if [ -x "$c" ]; then
      printf '%s\n' "$c"
      return
    fi
  done
  dsv41_die "ip(8) not found"
}

dsv41_systemctl() {
  if [ -n "${DSV41_SYSTEMCTL_BIN:-}" ]; then
    printf '%s\n' "$DSV41_SYSTEMCTL_BIN"
    return
  fi
  printf '%s\n' /usr/bin/systemctl
}

dsv41_curl() {
  if [ -n "${DSV41_CURL_BIN:-}" ]; then
    printf '%s\n' "$DSV41_CURL_BIN"
    return
  fi
  printf '%s\n' /usr/bin/curl
}

dsv41_docker() {
  if [ -n "${DSV41_DOCKER_BIN:-}" ]; then
    printf '%s\n' "$DSV41_DOCKER_BIN"
    return
  fi
  printf '%s\n' /usr/bin/docker
}

# Written by ready.sh after /health and an authenticated /v1/models both
# succeed. health.sh does not probe until this file exists and is older
# than the startup grace, so the cold load is not a watchdog strike.
dsv41_ready_flag() {
  printf '%s\n' "${XDG_RUNTIME_DIR:?}/dsv41-cluster.ready"
}

# Failure streak and the worker TCPStore baseline. Cleared when the head
# container is removed and while the ready flag is absent, so a streak
# from the previous generation cannot restart the next one.
dsv41_health_fail_file() {
  printf '%s\n' "${XDG_RUNTIME_DIR:?}/dsv41-cluster-health.fails"
}

dsv41_health_peer_file() {
  printf '%s\n' "${XDG_RUNTIME_DIR:?}/dsv41-cluster-health.peer"
}

dsv41_clear_health_state() {
  rm -f "$(dsv41_health_fail_file)" "$(dsv41_health_peer_file)"
}
