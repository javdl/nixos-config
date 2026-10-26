#!/usr/bin/env bash
# ExecStartPre for dsv41-mia.service. One subcommand in $1.
# Waits are bounded. Nothing here restarts a unit or prints a secret.
set -euo pipefail
set +x

mia_die() {
  echo "dsv41 mia: $*" >&2
  exit 1
}

require() {
  local name=$1
  if [ -z "${!name:-}" ]; then
    mia_die "${name} is unset"
  fi
}

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

ip_bin() {
  if [ -n "${MIA_IP_BIN:-}" ]; then
    printf '%s\n' "$MIA_IP_BIN"
    return
  fi
  local c
  for c in /usr/sbin/ip /sbin/ip /usr/bin/ip; do
    if [ -x "$c" ]; then
      printf '%s\n' "$c"
      return
    fi
  done
  mia_die "ip(8) not found"
}

ssh_bin() {
  printf '%s\n' "${MIA_SSH_BIN:-/usr/bin/ssh}"
}

docker_bin() {
  printf '%s\n' "${MIA_DOCKER_BIN:-/usr/bin/docker}"
}

git_bin() {
  printf '%s\n' "${MIA_GIT_BIN:-/usr/bin/git}"
}

systemctl_bin() {
  printf '%s\n' "${MIA_SYSTEMCTL_BIN:-/usr/bin/systemctl}"
}

ss_bin() {
  printf '%s\n' "${MIA_SS_BIN:-/usr/bin/ss}"
}

findmnt_bin() {
  printf '%s\n' "${MIA_FINDMNT_BIN:-/usr/bin/findmnt}"
}

fabric_up() {
  "$(ip_bin)" -4 addr show "$MIA_FAB_IF" 2>/dev/null | grep -qF "${MIA_HOST_IP}/" && return 0
  return 1
}

worker_up() {
  "$(ssh_bin)" -n -o BatchMode=yes -o ConnectTimeout=5 "$MIA_WORKER" true && return 0
  return 1
}

models_up() {
  local fstype
  [ -d "$MIA_MODELS" ] || return 1
  # Accessing the path trips the NAS automount. nfs* means the export is
  # actually mounted; autofs alone is not enough.
  fstype=$(timeout 15 "$(findmnt_bin)" -T "$MIA_MODELS" -n -o FSTYPE 2>/dev/null || true)
  case "$fstype" in
    nfs*) return 0 ;;
    *) return 1 ;;
  esac
}

unit_active() {
  # $1 is "user" or "system". A miss is not an error: the caller decides.
  local scope=$1 unit=$2
  if [ "$scope" = user ]; then
    "$(systemctl_bin)" --user is-active --quiet "$unit" && return 0
  else
    "$(systemctl_bin)" is-active --quiet "$unit" && return 0
  fi
  return 1
}

cmd=${1:-}
case "$cmd" in
  wait-fabric)
    require MIA_FAB_IF
    require MIA_HOST_IP
    require MIA_FABRIC_WAIT_SEC
    if ! wait_until "$MIA_FABRIC_WAIT_SEC" fabric_up; then
      mia_die "${MIA_HOST_IP} did not appear on ${MIA_FAB_IF} within ${MIA_FABRIC_WAIT_SEC}s"
    fi
    ;;
  wait-worker)
    require MIA_WORKER
    require MIA_WORKER_WAIT_SEC
    if ! wait_until "$MIA_WORKER_WAIT_SEC" worker_up; then
      mia_die "ssh to ${MIA_WORKER} failed for ${MIA_WORKER_WAIT_SEC}s (rank 1 is started over that ssh; spark2 has no unit)"
    fi
    ;;
  wait-models)
    require MIA_MODELS
    require MIA_MODELS_WAIT_SEC
    if ! wait_until "$MIA_MODELS_WAIT_SEC" models_up; then
      mia_die "${MIA_MODELS} was not an nfs mount within ${MIA_MODELS_WAIT_SEC}s"
    fi
    ;;
  preflight)
    require MIA_RECIPE
    require MIA_REV
    require MIA_IMAGE
    require MIA_MODELS
    require MIA_SHIM
    require MIA_PORT
    require MIA_WORKER
    if [ ! -f "$MIA_RECIPE/start.sh" ] || [ ! -f "$MIA_RECIPE/stop.sh" ]; then
      mia_die "recipe launcher missing under ${MIA_RECIPE} (expected start.sh and stop.sh)"
    fi
    if [ ! -f "$MIA_RECIPE/scripts/local.sh" ]; then
      mia_die "missing ${MIA_RECIPE}/scripts/local.sh. NAS paths stay in that file; this unit does not write it"
    fi
    if ! grep -qF "$MIA_MODELS" "$MIA_RECIPE/scripts/local.sh"; then
      mia_die "scripts/local.sh does not mention ${MIA_MODELS}. Refusing to start against the recipe's default cache"
    fi
    got=$("$(git_bin)" -C "$MIA_RECIPE" rev-parse HEAD)
    if [ "$got" != "$MIA_REV" ]; then
      mia_die "recipe HEAD is ${got}, pinned launcher is ${MIA_REV}. Update the checkout or the pin in users/dsv41-mia.nix together"
    fi
    if ! "$(git_bin)" -C "$MIA_RECIPE" diff --quiet -- start.sh stop.sh scripts/config.sh scripts/nodes.sh scripts/prepare.sh; then
      mia_die "start.sh, stop.sh, or scripts/{config,nodes,prepare}.sh differ from ${MIA_REV}. The unit runs that pin; stash the edits or move the pin"
    fi
    if [ ! -d "$MIA_SHIM" ]; then
      mia_die "shim directory missing: ${MIA_SHIM}"
    fi
    if ! "$(docker_bin)" image inspect "$MIA_IMAGE" >/dev/null 2>&1; then
      mia_die "image not present locally (PREPARE=0 does not build it): ${MIA_IMAGE}"
    fi
    # Rank 1 is `docker run` over ssh. A missing image or NAS directory on
    # spark2 fails only after rank 0 has started, so check both first.
    if ! "$(ssh_bin)" -n -o BatchMode=yes -o ConnectTimeout=10 "$MIA_WORKER" \
      "docker image inspect $(printf '%q' "$MIA_IMAGE") >/dev/null"; then
      mia_die "image not present on ${MIA_WORKER} (PREPARE=0 does not ship it): ${MIA_IMAGE}"
    fi
    if ! "$(ssh_bin)" -n -o BatchMode=yes -o ConnectTimeout=10 "$MIA_WORKER" \
      "test -d $(printf '%q' "$MIA_MODELS")"; then
      mia_die "${MIA_MODELS} is not a directory on ${MIA_WORKER}"
    fi
    if "$(ss_bin)" -ltn "sport = :${MIA_PORT}" 2>/dev/null | grep -q LISTEN; then
      mia_die "port ${MIA_PORT} is already in use. Stop the current server first (systemctl --user stop mia29-tf, then the recipe stop.sh if a rank is left). start.sh exits 0 when both ranks are already up, and this unit would not supervise them"
    fi
    if unit_active user mia29-tf.service; then
      mia_die "transient unit mia29-tf.service is still active. Stop it, and mia29-faultwatch.service, before starting dsv41-mia"
    fi
    for unit in spark-vllm.service nvpair.service; do
      if unit_active system "$unit" || unit_active user "$unit"; then
        mia_die "${unit} is active. Stop and disable it before starting Mia (GB10 unified memory). This unit does not stop a system unit"
      fi
    done
    ;;
  *)
    mia_die "usage: mia-prepare.sh wait-fabric|wait-worker|wait-models|preflight"
    ;;
esac
