#!/usr/bin/env bash
# Exercise the Mia preflight, the raw API-key handoff, and the log-only probe.
# No cluster, no docker, no ssh.
set -euo pipefail
set +x

script_dir=$(CDPATH= cd -- "${1:?script dir}" && pwd)
mia_nix=${2:?mia nix}
cluster_nix=${3:?cluster nix}
spark_nix=${4:?spark profile}
key_value=sk-test-mia-9f3c

fail() {
  printf 'dsv41 mia: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  if [ "$1" != "$2" ]; then
    fail "$3"
  fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

write_stubs() {
  cat >"$work/git" <<'EOF'
#!/bin/sh
shift 2
if [ "$1" = rev-parse ]; then
  printf '%s\n' "${FAKE_REV:?}"
  exit 0
fi
if [ "$1" = diff ]; then
  exit "${FAKE_DIFF_RC:-0}"
fi
echo "unexpected git: $*" >&2
exit 2
EOF
  cat >"$work/docker" <<'EOF'
#!/bin/sh
if [ "$1" = image ] && [ "$2" = inspect ]; then
  if [ "$3" = "${EXPECT_IMAGE:?}" ]; then
    exit 0
  fi
  exit 1
fi
exit 1
EOF
  cat >"$work/ss" <<'EOF'
#!/bin/sh
if [ "${PORT_BUSY:-0}" = 1 ]; then
  echo "LISTEN 0 128 127.0.0.1:8000 0.0.0.0:*"
fi
exit 0
EOF
  cat >"$work/ip" <<'EOF'
#!/bin/sh
if [ "${FABRIC_UP:-1}" = 1 ]; then
  echo "    inet 192.168.100.10/24 brd 192.168.100.255 scope global enp1s0f0np0"
else
  echo "    inet 10.0.0.1/24 brd 10.0.0.255 scope global eth0"
fi
exit 0
EOF
  cat >"$work/ssh" <<'EOF'
#!/bin/sh
[ "${SSH_OK:-1}" = 1 ] || exit 1
if printf '%s' "$*" | grep -q 'image inspect'; then
  [ "${REMOTE_IMAGE_OK:-1}" = 1 ] || exit 1
fi
if printf '%s' "$*" | grep -q 'test -d'; then
  [ "${REMOTE_MODELS_OK:-1}" = 1 ] || exit 1
fi
exit 0
EOF
  cat >"$work/findmnt" <<'EOF'
#!/bin/sh
# FINDMNT_FSTYPE is the literal stdout, including a stacked autofs+nfs4
# listing. Unset, NFS_OK selects the single-line fixture.
if [ -n "${FINDMNT_FSTYPE+x}" ]; then
  printf '%s\n' "$FINDMNT_FSTYPE"
  exit 0
fi
if [ "${NFS_OK:-1}" = 1 ]; then
  echo nfs4
else
  echo ext4
fi
EOF
  cat >"$work/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${SYSLOG:?}"
unit=
for arg in "$@"; do
  case "$arg" in
    --* | is-active | show) ;;
    *) unit=$arg ;;
  esac
done
case " ${ACTIVE:-} " in
  *" $unit "*) exit 0 ;;
esac
exit 1
EOF
  cat >"$work/systemctl-health" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${SYSLOG:?}"
if [ "$1" = --user ]; then
  shift
fi
cmd=$1
shift
case "$cmd" in
  is-active)
    if [ "${HEALTH_ACTIVE:-0}" = 1 ]; then
      exit 0
    fi
    exit 1
    ;;
  show)
    printf '%s\n' "${HEALTH_STAMP:-}"
    exit 0
    ;;
esac
echo "unexpected systemctl: $cmd" >&2
exit 2
EOF
  cat >"$work/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${CURLLOG:?}"
exit "${CURL_RC:-0}"
EOF
  chmod 755 "$work/git" "$work/docker" "$work/ss" "$work/ip" "$work/ssh" \
    "$work/findmnt" "$work/systemctl" "$work/systemctl-health" "$work/curl"
}

recipe_fixture() {
  local recipe=$1 models=$2
  mkdir -p "$recipe/scripts"
  printf '%s\n' '#!/bin/sh' >"$recipe/start.sh"
  printf '%s\n' '#!/bin/sh' >"$recipe/stop.sh"
  printf '%s\n' '# pin' >"$recipe/scripts/config.sh"
  printf '%s\n' '# pin' >"$recipe/scripts/nodes.sh"
  printf '%s\n' '# pin' >"$recipe/scripts/prepare.sh"
  printf '%s\n' "HF_CACHE=${models}/hf" >"$recipe/scripts/local.sh"
}

prepare_env() {
  local recipe=$1 shim=$2 models=$3
  export MIA_RECIPE=$recipe
  export MIA_REV=370daf0cc38f348516a98ebab38f6053858eab1f
  export MIA_IMAGE=tensorfold-dsv41:exl3-tp2-625d420e24a4
  export MIA_WORKER=joost@192.168.100.11
  export MIA_MODELS=$models
  export MIA_SHIM=$shim
  export MIA_PORT=8000
  export MIA_FAB_IF=enp1s0f0np0
  export MIA_HOST_IP=192.168.100.10
  export MIA_FABRIC_WAIT_SEC=120
  export MIA_WORKER_WAIT_SEC=180
  export MIA_MODELS_WAIT_SEC=120
  export MIA_GIT_BIN=$work/git
  export MIA_DOCKER_BIN=$work/docker
  export MIA_SS_BIN=$work/ss
  export MIA_IP_BIN=$work/ip
  export MIA_SSH_BIN=$work/ssh
  export MIA_FINDMNT_BIN=$work/findmnt
  export MIA_SYSTEMCTL_BIN=$work/systemctl
  export FAKE_REV=$MIA_REV
  export FAKE_DIFF_RC=0
  export EXPECT_IMAGE=$MIA_IMAGE
  export PORT_BUSY=0
  export FABRIC_UP=1
  export SSH_OK=1
  export REMOTE_IMAGE_OK=1
  export REMOTE_MODELS_OK=1
  export NFS_OK=1
  unset FINDMNT_FSTYPE
  export ACTIVE=
  export SYSLOG=$work/syslog
  : >"$SYSLOG"
}

run_prepare() {
  bash "$script_dir/mia-prepare.sh" "$@"
}

write_stubs
recipe=$work/recipe
shim=$work/shimw
models=$work/models/mia29
mkdir -p "$shim" "$models"
recipe_fixture "$recipe" "$models"
prepare_env "$recipe" "$shim" "$models"

# Happy path: pin matches, NAS path is in local.sh, port is free, image exists.
run_prepare preflight

# A moved checkout is refused before anything is launched.
FAKE_REV=0000000000000000000000000000000000000000
if run_prepare preflight >"$work/out" 2>"$work/err"; then
  fail "preflight accepted a different recipe HEAD"
fi
grep -q 'pinned launcher' "$work/err"
FAKE_REV=$MIA_REV

# Dirty launcher scripts are refused. local.sh is allowed to differ.
FAKE_DIFF_RC=1
if run_prepare preflight >"$work/out" 2>"$work/err"; then
  fail "preflight accepted a dirty launcher"
fi
grep -q 'differ from' "$work/err"
FAKE_DIFF_RC=0

# Weights must be the NAS tree named in local.sh, not the recipe default cache.
printf '%s\n' 'HF_CACHE=/tmp/not-the-nas' >"$recipe/scripts/local.sh"
if run_prepare preflight >"$work/out" 2>"$work/err"; then
  fail "preflight accepted local.sh without the NAS path"
fi
grep -qF "$models" "$work/err"
printf '%s\n' "HF_CACHE=${models}/hf" >"$recipe/scripts/local.sh"

# An already-listening port must not be adopted. start.sh would exit 0.
PORT_BUSY=1
if run_prepare preflight >"$work/out" 2>"$work/err"; then
  fail "preflight accepted a busy port"
fi
grep -q 'already in use' "$work/err"
PORT_BUSY=0

# The hand-started transient unit must be stopped before this one starts.
ACTIVE=mia29-tf.service
if run_prepare preflight >"$work/out" 2>"$work/err"; then
  fail "preflight accepted a live mia29-tf"
fi
grep -q 'mia29-tf' "$work/err"
ACTIVE=

# spark-vllm and nvpair stay stopped. Check both managers.
ACTIVE=spark-vllm.service
if run_prepare preflight >"$work/out" 2>"$work/err"; then
  fail "preflight accepted an active spark-vllm"
fi
grep -q 'spark-vllm' "$work/err"
ACTIVE=nvpair.service
if run_prepare preflight >"$work/out" 2>"$work/err"; then
  fail "preflight accepted an active nvpair"
fi
grep -q 'nvpair' "$work/err"
ACTIVE=

EXPECT_IMAGE=missing:tag
if run_prepare preflight >"$work/out" 2>"$work/err"; then
  fail "preflight accepted a missing image"
fi
grep -q 'image not present' "$work/err"
EXPECT_IMAGE=$MIA_IMAGE

REMOTE_IMAGE_OK=0
if run_prepare preflight >"$work/out" 2>"$work/err"; then
  fail "preflight accepted a worker without the image"
fi
grep -q 'not present on' "$work/err"
REMOTE_IMAGE_OK=1

REMOTE_MODELS_OK=0
if run_prepare preflight >"$work/out" 2>"$work/err"; then
  fail "preflight accepted a worker without the NAS directory"
fi
grep -q 'not a directory on' "$work/err"
REMOTE_MODELS_OK=1

# Bounded waits.
MIA_FABRIC_WAIT_SEC=1
FABRIC_UP=0
if run_prepare wait-fabric >"$work/out" 2>"$work/err"; then
  fail "wait-fabric succeeded without the CX7 address"
fi
grep -q 'did not appear' "$work/err"
FABRIC_UP=1
MIA_FABRIC_WAIT_SEC=120
run_prepare wait-fabric

MIA_WORKER_WAIT_SEC=1
SSH_OK=0
if run_prepare wait-worker >"$work/out" 2>"$work/err"; then
  fail "wait-worker succeeded without ssh"
fi
grep -q 'ssh to' "$work/err"
SSH_OK=1
MIA_WORKER_WAIT_SEC=180
run_prepare wait-worker

MIA_MODELS_WAIT_SEC=1
NFS_OK=0
if run_prepare wait-models >"$work/out" 2>"$work/err"; then
  fail "wait-models accepted a non-nfs path"
fi
grep -q 'not an nfs mount' "$work/err"
NFS_OK=1
rmdir "$models"
if run_prepare wait-models >"$work/out" 2>"$work/err"; then
  fail "wait-models accepted a missing directory"
fi
mkdir -p "$models"
MIA_MODELS_WAIT_SEC=120
run_prepare wait-models

# Spark NAS: the automount and the export are stacked, so findmnt prints
# autofs and then nfs4. nfs on any line is enough, and it must not wait
# out the deadline.
FINDMNT_FSTYPE=$'autofs\nnfs4'
export FINDMNT_FSTYPE
MIA_MODELS_WAIT_SEC=1
if ! run_prepare wait-models >"$work/out" 2>"$work/err"; then
  fail "wait-models rejected stacked autofs+nfs4"
fi
if [ -s "$work/err" ]; then
  fail "wait-models logged an error for stacked autofs+nfs4"
fi

# Idle automount: only autofs. The directory stat still runs, then the
# bounded wait expires and the start fails.
FINDMNT_FSTYPE=autofs
start=$SECONDS
if run_prepare wait-models >"$work/out" 2>"$work/err"; then
  fail "wait-models accepted an idle autofs mount"
fi
if [ $((SECONDS - start)) -lt 1 ]; then
  fail "wait-models failed an idle autofs mount without waiting"
fi
grep -q 'not an nfs mount' "$work/err"
unset FINDMNT_FSTYPE
MIA_MODELS_WAIT_SEC=120

# Raw key handoff. The value is the production VLLM_API_KEY, unquoted, mode 600.
src=$work/api.env
dest=$work/state/api-key
umask 077
printf 'OTHER=1\nVLLM_API_KEY="%s"\n' "$key_value" >"$src"
chmod 600 "$src"
export DSV41_API_KEY_FILE=$src
if ! bash "$script_dir/api-key.sh" write-raw "$dest" >"$work/out" 2>"$work/err"; then
  fail "write-raw failed for a quoted key"
fi
printf '%s\n' "$key_value" >"$work/expect"
cmp -s "$work/expect" "$dest" || fail "quoted key was not written raw"
assert_eq "$(stat -c '%a' "$dest")" 600 "raw key mode"
if grep -qF "$key_value" "$work/err" "$work/out"; then
  fail "write-raw printed the key"
fi

printf 'VLLM_API_KEY=%s\n' "$key_value" >"$src"
chmod 600 "$src"
rm -f "$dest"
bash "$script_dir/api-key.sh" write-raw "$dest" >"$work/out" 2>"$work/err"
cmp -s "$work/expect" "$dest" || fail "unquoted key was not written raw"

chmod 644 "$src"
if bash "$script_dir/api-key.sh" write-raw "$dest" >"$work/out" 2>"$work/err"; then
  fail "write-raw accepted a mode 644 source"
fi
grep -q 'mode 600' "$work/err"
chmod 600 "$src"

ln -s real "$work/state/link"
printf '%s\n' old >"$work/state/real"
if bash "$script_dir/api-key.sh" write-raw "$work/state/link" >"$work/out" 2>"$work/err"; then
  fail "write-raw followed a symlink"
fi
grep -q 'symlink' "$work/err"
assert_eq "$(cat "$work/state/real")" old "symlink target changed"
rm "$work/state/link"

# write-env still strips one pair of quotes for the sybil docker env-file.
runtime=$work/run
mkdir -p "$runtime"
cluster_env=$work/cluster.env
cat >"$cluster_env" <<EOF
DSV41_EXPOSE=aperture
DSV41_ROLE=head
DSV41_API_KEY_FILE=$src
EOF
printf 'VLLM_API_KEY="%s"\n' "$key_value" >"$src"
chmod 600 "$src"
DSV41_CLUSTER_ENV=$cluster_env XDG_RUNTIME_DIR=$runtime \
  bash "$script_dir/api-key.sh" write-env >"$work/out" 2>"$work/err"
printf 'VLLM_API_KEY=%s\n' "$key_value" >"$work/expect-env"
cmp -s "$work/expect-env" "$runtime/dsv41-cluster-api.env" || fail "write-env quote strip regressed"
if grep -qF "$key_value" "$work/err" "$work/out"; then
  fail "write-env printed the key"
fi
unset DSV41_CLUSTER_ENV

# Log-only probe: no restart, quiet while the unit is down or still loading.
export MIA_SYSTEMCTL_BIN=$work/systemctl-health
export MIA_CURL_BIN=$work/curl
export MIA_DATE_BIN=$(command -v date)
export MIA_HEALTH_GRACE_SEC=900
export MIA_HEALTH_URL=http://127.0.0.1:8000/health
export CURLLOG=$work/curl.log
export HEALTH_ACTIVE=0
export HEALTH_STAMP=
export CURL_RC=1
: >"$SYSLOG"
: >"$CURLLOG"
bash "$script_dir/mia-health.sh" >"$work/out" 2>"$work/err"
assert_eq "$(cat "$work/err")" "" "inactive probe was not quiet"
assert_eq "$(cat "$CURLLOG")" "" "inactive probe contacted /health"
if grep -q restart "$SYSLOG"; then
  fail "inactive probe restarted something"
fi

HEALTH_ACTIVE=1
HEALTH_STAMP=$(date +%s%6N)
: >"$SYSLOG"
: >"$CURLLOG"
bash "$script_dir/mia-health.sh" >"$work/out" 2>"$work/err"
assert_eq "$(cat "$work/err")" "" "young probe logged a failure"
assert_eq "$(cat "$CURLLOG")" "" "young probe contacted /health"

HEALTH_STAMP=1000000
CURL_RC=0
: >"$SYSLOG"
: >"$CURLLOG"
bash "$script_dir/mia-health.sh" >"$work/out" 2>"$work/err"
assert_eq "$(cat "$work/err")" "" "healthy probe logged a failure"
test -s "$CURLLOG"

CURL_RC=1
: >"$SYSLOG"
: >"$CURLLOG"
bash "$script_dir/mia-health.sh" >"$work/out" 2>"$work/err"
grep -q 'Not restarting.' "$work/err"
if grep -q restart "$SYSLOG"; then
  fail "health probe restarted the unit"
fi

# The declared pin and the off switch for the sybil units.
grep -q '370daf0cc38f348516a98ebab38f6053858eab1f' "$mia_nix"
grep -q 'tensorfold-dsv41:exl3-tp2-625d420e24a4' "$mia_nix"
grep -q 'hostName == "spark"' "$mia_nix"
grep -q 'Restart = "on-failure"' "$mia_nix"
grep -q 'default = false;' "$cluster_nix"
if grep -q 'After = \[ "dsv41-cluster-head.service" \]' "$cluster_nix"; then
  fail "sybil health timer still orders After= the head"
fi
grep -q 'mkIf (isHead && aperture)' "$cluster_nix"
grep -q 'dsv41-mia.nix' "$spark_nix"
grep -q 'services.dsv41Cluster.enable = false;' "$spark_nix"
grep -q 'services.dsv41Mia.enable = true;' "$spark_nix"
if grep -q 'systemctl.*restart' "$script_dir/mia-health.sh"; then
  fail "mia-health.sh contains a restart command"
fi

printf '%s\n' "dsv41 mia checks passed."
