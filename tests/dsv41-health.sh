#!/usr/bin/env bash
# Exercise users/dsv41/health.sh without a cluster. curl, systemctl,
# /proc/net/tcp, and /proc/net/tcp6 are fixtures. The API key must not
# appear in the output.
set -euo pipefail

script_dir=$(CDPATH= cd -- "${1:-$(dirname "$0")/../users/dsv41}" && pwd)
key_value=dsv41-test-key-9f3c2a7b

if [ ! -x "$script_dir/health.sh" ] && [ ! -f "$script_dir/health.sh" ]; then
  echo "health.sh not found in ${script_dir}" >&2
  exit 1
fi

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local got=$1 expected=$2 label=$3
  if [ "$got" != "$expected" ]; then
    fail "${label}: expected [${expected}] got [${got}]"
  fi
}

restart_count() {
  if [ -f "$restarts" ]; then
    wc -l <"$restarts" | tr -d ' '
  else
    printf '0\n'
  fi
}

# Worker 192.168.100.11 is 0B64A8C0. Master port 25000 is 61A8.
# A listen socket, a localhost client, and a TIME_WAIT worker socket are
# noise the parser must ignore.
write_tcp() {
  local p i=3
  {
    printf '%s\n' "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode"
    printf '%s\n' "   0: 0A64A8C0:61A8 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 1 1 0000000000000000 100 0 0 10 0"
    printf '%s\n' "   1: 0A64A8C0:61A8 0100007F:1234 01 00000000:00000000 00:00000000 00000000     0        0 2 1 0000000000000000 100 0 0 10 0"
    printf '%s\n' "   2: 0A64A8C0:61A8 0B64A8C0:1111 06 00000000:00000000 00:00000000 00000000     0        0 3 1 0000000000000000 100 0 0 10 0"
    for p in "$@"; do
      printf '   %s: 0A64A8C0:61A8 0B64A8C0:%s 01 00000000:00000000 00:00000000 00000000     0        0 %s 1 0000000000000000 100 0 0 10 0\n' "$i" "$p" "$i"
      i=$((i + 1))
    done
  } >"$tcp"
}

# IPv4-mapped worker is 0000000000000000FFFF00000B64A8C0 (the tcp4 address
# with the ::ffff: prefix the kernel prints in tcp6). Noise: a wildcard
# listen, a native IPv6 client, a TIME_WAIT mapped socket, an established
# socket to a different IPv4, and an established mapped socket on the
# wrong local port.
write_tcp6() {
  local p i=6
  {
    printf '%s\n' "  sl  local_address                         remote_address                        st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode"
    printf '%s\n' "   0: 00000000000000000000000000000000:61A8 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 1 1 0000000000000000 100 0 0 10 0"
    printf '%s\n' "   1: 00000000000000000000000000000000:61A8 20010DB8000000000000000000000001:ABCD 01 00000000:00000000 00:00000000 00000000     0        0 2 1 0000000000000000 100 0 0 10 0"
    printf '%s\n' "   2: 0000000000000000FFFF00000A64A8C0:61A8 0000000000000000FFFF00000B64A8C0:1111 06 00000000:00000000 00:00000000 00000000     0        0 3 1 0000000000000000 100 0 0 10 0"
    printf '%s\n' "   3: 0000000000000000FFFF00000A64A8C0:61A8 0000000000000000FFFF00000C64A8C0:9C40 01 00000000:00000000 00:00000000 00000000     0        0 4 1 0000000000000000 100 0 0 10 0"
    printf '%s\n' "   4: 0000000000000000FFFF00000A64A8C0:0050 0000000000000000FFFF00000B64A8C0:9C42 01 00000000:00000000 00:00000000 00000000     0        0 5 1 0000000000000000 100 0 0 10 0"
    for p in "$@"; do
      printf '   %s: 0000000000000000FFFF00000A64A8C0:61A8 0000000000000000FFFF00000B64A8C0:%s 01 00000000:00000000 00:00000000 00000000     0        0 %s 1 0000000000000000 100 0 0 10 0\n' "$i" "$p" "$i"
      i=$((i + 1))
    done
  } >"$tcp6"
}

new_case() {
  runtime=$(mktemp -d)
  work=$(mktemp -d)
  keyfile=$work/api.env
  envfile=$work/cluster.env
  tcp=$work/net.tcp
  tcp6=$work/net.tcp6
  restarts=$work/restarts
  curl_log=$work/curl.log
  auth_log=$work/auth.log
  sys_log=$work/systemctl.log
  umask 077
  printf 'VLLM_API_KEY=%s\n' "$key_value" >"$keyfile"
  chmod 600 "$keyfile"
  cat >"$envfile" <<EOF
DSV41_PORT=8000
DSV41_SERVED=dsv41
DSV41_HEALTH_FAILURES=5
DSV41_HEALTH_TIMEOUT_SEC=20
DSV41_HEALTH_GRACE_SEC=60
DSV41_HEALTH_PEER_CONFIRMS=2
DSV41_WORKER_IP=192.168.100.11
DSV41_MASTER_PORT=25000
DSV41_EXPOSE=aperture
DSV41_API_KEY_FILE=$keyfile
DSV41_ROLE=head
DSV41_CONTAINER=dsv41-serve
EOF
  # /bin/sh shebangs: the flake-check sandbox has no /usr/bin/env.
  cat >"$work/systemctl" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${DSV41_TEST_SYSTEMCTL_LOG:?}"
if [ "${2:-}" = "is-active" ]; then
  if [ -n "${DSV41_TEST_HEAD_DOWN:-}" ]; then
    exit 1
  fi
  exit 0
fi
if [ "${2:-}" = "restart" ]; then
  printf '%s\n' restart >>"${DSV41_TEST_RESTARTS:?}"
  exit 0
fi
exit 0
EOF
  cat >"$work/curl" <<'EOF'
#!/bin/sh
set -eu
url=
for a in "$@"; do
  url=$a
done
printf '%s\n' "$url" >>"${DSV41_TEST_CURL_LOG:?}"
case "$url" in
  */health)
    if [ "${DSV41_TEST_HEALTH_CODE:-200}" = 200 ]; then
      exit 0
    fi
    exit 1
    ;;
  */v1/chat/completions)
    prev= max= cfg=
    for a in "$@"; do
      if [ "$prev" = "--max-time" ]; then
        max=$a
      fi
      if [ "$prev" = "--config" ]; then
        cfg=$a
      fi
      prev=$a
    done
    if [ "$max" != "20" ]; then
      printf 'expected chat max-time 20, got %s\n' "${max:-none}" >&2
      exit 1
    fi
    if [ -n "${cfg:-}" ] && [ -n "${DSV41_TEST_KEY:-}" ]; then
      if grep -q -F "Authorization: Bearer ${DSV41_TEST_KEY}" "$cfg"; then
        printf '%s\n' saw-auth >>"${DSV41_TEST_AUTH_LOG:?}"
      fi
    fi
    code=${DSV41_TEST_CHAT_CODE:-200}
    if [ "$code" = timeout ]; then
      printf '%s' 000
      exit 28
    fi
    printf '%s' "$code"
    exit 0
    ;;
  */metrics)
    prev= max= cfg= out=
    for a in "$@"; do
      if [ "$prev" = "--max-time" ]; then
        max=$a
      fi
      if [ "$prev" = "--config" ]; then
        cfg=$a
      fi
      if [ "$prev" = "-o" ]; then
        out=$a
      fi
      prev=$a
    done
    if [ "$max" != "5" ]; then
      printf 'expected metrics max-time 5, got %s\n' "${max:-none}" >&2
      exit 1
    fi
    if [ -n "${cfg:-}" ] && [ -n "${DSV41_TEST_KEY:-}" ]; then
      if grep -q -F "Authorization: Bearer ${DSV41_TEST_KEY}" "$cfg"; then
        printf '%s\n' saw-auth >>"${DSV41_TEST_AUTH_LOG:?}"
      fi
    fi
    mode=${DSV41_TEST_METRICS:-fail}
    if [ "$mode" = fail ]; then
      printf '%s' 000
      exit 1
    fi
    n=0
    if [ -n "${DSV41_TEST_METRICS_STATE:-}" ] && [ -f "$DSV41_TEST_METRICS_STATE" ]; then
      n=$(cat "$DSV41_TEST_METRICS_STATE")
    fi
    n=$((n + 1))
    if [ -n "${DSV41_TEST_METRICS_STATE:-}" ]; then
      printf '%s\n' "$n" >"$DSV41_TEST_METRICS_STATE"
    fi
    running=1
    prompt=1000
    gen=50
    case "$mode" in
      frozen) ;;
      advance-prompt)
        prompt=$((n * 30000))
        ;;
      advance-gen)
        gen=$((n * 8))
        ;;
      drop)
        if [ "$n" -ge 2 ]; then
          prompt=10
          gen=1
        else
          prompt=5000
          gen=100
        fi
        ;;
      idle)
        running=0
        ;;
      *)
        printf 'unknown metrics mode %s\n' "$mode" >&2
        exit 1
        ;;
    esac
    if [ -z "$out" ]; then
      printf 'metrics curl missing -o\n' >&2
      exit 1
    fi
    {
      printf '%s\n' '# HELP vllm:num_requests_running Number of requests running.'
      printf '%s\n' '# TYPE vllm:num_requests_running gauge'
      printf 'vllm:num_requests_running{model_name="dsv41"} %s\n' "$running"
      # A later 0 must be summed, not overwrite the gauge above.
      printf '%s\n' 'num_requests_running{model_name="other"} 0'
      # Unprefixed prompt counter. A bucket that grows must not count.
      printf 'prompt_tokens_total{model_name="dsv41"} %s\n' "$prompt"
      printf 'prompt_tokens_total{model_name="draft"} 5\n'
      printf 'vllm:generation_tokens_total{model_name="dsv41"} %s\n' "$gen"
      printf 'vllm:prompt_tokens_total_bucket{le="+Inf"} %s\n' "$((n * 1000000))"
      printf 'prompt_tokens_created %s\n' "$((n * 1000000))"
    } >"$out"
    printf '%s' 200
    exit 0
    ;;
esac
printf 'unexpected url %s\n' "$url" >&2
exit 1
EOF
  cat >"$work/docker" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod 755 "$work/systemctl" "$work/curl" "$work/docker"
  write_tcp 9C40
  write_tcp6
  export XDG_RUNTIME_DIR=$runtime
  export DSV41_CLUSTER_ENV=$envfile
  export DSV41_SYSTEMCTL_BIN=$work/systemctl
  export DSV41_CURL_BIN=$work/curl
  export DSV41_DOCKER_BIN=$work/docker
  export DSV41_PROC_NET_TCP=$tcp
  export DSV41_PROC_NET_TCP6=$tcp6
  export DSV41_TEST_SYSTEMCTL_LOG=$sys_log
  export DSV41_TEST_RESTARTS=$restarts
  export DSV41_TEST_CURL_LOG=$curl_log
  export DSV41_TEST_AUTH_LOG=$auth_log
  export DSV41_TEST_KEY=$key_value
  export DSV41_TEST_METRICS_STATE=$work/metrics.n
  unset DSV41_TEST_HEAD_DOWN DSV41_TEST_HEALTH_CODE DSV41_TEST_CHAT_CODE DSV41_TEST_METRICS
}

ready_old() {
  printf '%s\n' ready >"$runtime/dsv41-cluster.ready"
  touch -d '2020-01-01 00:00:00' "$runtime/dsv41-cluster.ready"
}

ready_now() {
  printf '%s\n' ready >"$runtime/dsv41-cluster.ready"
}

run_health() {
  : >"$curl_log"
  set +e
  bash "$script_dir/health.sh" >"$work/out" 2>"$work/err"
  rc=$?
  set -e
}

assert_clean_secret() {
  if grep -R -F -q -- "$key_value" "$runtime" "$work/out" "$work/err" "$curl_log" "$sys_log" "$auth_log" 2>/dev/null; then
    fail "API key leaked into watchdog output or runtime files"
  fi
}

# --- head not running ---
new_case
export DSV41_TEST_HEAD_DOWN=1
ready_old
run_health
assert_eq "$rc" 0 "head down rc"
assert_eq "$(restart_count)" 0 "head down restarts"
assert_eq "$(wc -c <"$curl_log" | tr -d ' ')" 0 "head down made no HTTP call"
unset DSV41_TEST_HEAD_DOWN

# --- cold load: no ready flag ---
new_case
export DSV41_TEST_HEALTH_CODE=000
printf '%s\n' 4 >"$runtime/dsv41-cluster-health.fails"
printf 'prompt=1\ngeneration=1\n' >"$runtime/dsv41-cluster-health.metrics"
run_health
assert_eq "$rc" 0 "not ready rc"
assert_eq "$(restart_count)" 0 "not ready restarts"
grep -q 'skipping the chat probe' "$work/err"
if grep -q chat/completions "$curl_log"; then
  fail "chat probe ran before ready"
fi
if [ -e "$runtime/dsv41-cluster-health.fails" ] || [ -e "$runtime/dsv41-cluster-health.metrics" ]; then
  fail "failure streak survived the not-ready skip"
fi

new_case
export DSV41_TEST_HEALTH_CODE=200
run_health
grep -q 'waits for dsv41-cluster-ready' "$work/err"
if grep -q chat/completions "$curl_log"; then
  fail "chat probe ran when /health was up but ready was not"
fi

# --- startup grace ---
new_case
ready_now
printf '%s\n' 4 >"$runtime/dsv41-cluster-health.fails"
printf 'id=9C40\nstreak=1\n' >"$runtime/dsv41-cluster-health.peer"
printf 'prompt=1\ngeneration=1\n' >"$runtime/dsv41-cluster-health.metrics"
run_health
assert_eq "$rc" 0 "grace rc"
assert_eq "$(restart_count)" 0 "grace restarts"
grep -q 'startup grace' "$work/err"
assert_eq "$(wc -c <"$curl_log" | tr -d ' ')" 0 "grace made no HTTP call"
if [ -e "$runtime/dsv41-cluster-health.fails" ] || [ -e "$runtime/dsv41-cluster-health.peer" ] || [ -e "$runtime/dsv41-cluster-health.metrics" ]; then
  fail "grace did not clear a streak from the previous generation"
fi

# --- successful chat arms the worker baseline and sends the key ---
new_case
ready_old
export DSV41_TEST_CHAT_CODE=200
export DSV41_TEST_HEALTH_CODE=200
run_health
assert_eq "$rc" 0 "chat 200 rc"
assert_eq "$(restart_count)" 0 "chat 200 restarts"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 0 "chat 200 clears failures"
assert_eq "$(sed -n '1p' "$runtime/dsv41-cluster-health.peer")" "id=9C40" "baseline port"
grep -q saw-auth "$auth_log"
if grep -q '/metrics' "$curl_log"; then
  fail "chat 200 scraped /metrics"
fi
assert_clean_secret

# --- four chat timeouts are not a restart; the fifth is. A 200 in between clears. ---
new_case
ready_old
export DSV41_TEST_CHAT_CODE=200
run_health
export DSV41_TEST_CHAT_CODE=timeout
i=0
while [ "$i" -lt 4 ]; do
  run_health
  i=$((i + 1))
done
assert_eq "$(restart_count)" 0 "four timeouts restarted"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 4 "four timeouts counted"
grep -q '/metrics' "$curl_log"
assert_eq "$(sed -n '1p' "$runtime/dsv41-cluster-health.peer")" "id=9C40" "timeouts kept the baseline"
export DSV41_TEST_CHAT_CODE=200
run_health
assert_eq "$(restart_count)" 0 "recovery restarted"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 0 "recovery cleared the streak"
export DSV41_TEST_CHAT_CODE=timeout
i=0
while [ "$i" -lt 5 ]; do
  run_health
  i=$((i + 1))
done
assert_eq "$(restart_count)" 1 "fifth timeout restarts once"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 0 "restart resets the streak"
if [ -e "$runtime/dsv41-cluster-health.peer" ]; then
  fail "restart left the worker baseline in place"
fi

# --- 401 is a key mismatch, not a strike ---
new_case
ready_old
export DSV41_TEST_CHAT_CODE=200
run_health
printf '%s\n' 2 >"$runtime/dsv41-cluster-health.fails"
export DSV41_TEST_CHAT_CODE=401
run_health
assert_eq "$rc" 1 "401 rc"
assert_eq "$(restart_count)" 0 "401 restarts"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 2 "401 did not count a strike"
grep -q 'returned 401' "$work/err"
if grep -q '/metrics' "$curl_log"; then
  fail "401 scraped /metrics"
fi
assert_clean_secret

# --- /health down counts, and five downs restart ---
new_case
ready_old
export DSV41_TEST_HEALTH_CODE=000
i=0
while [ "$i" -lt 4 ]; do
  run_health
  i=$((i + 1))
done
assert_eq "$(restart_count)" 0 "four /health failures restarted"
if grep -q chat/completions "$curl_log"; then
  fail "chat probe ran when /health was down"
fi
if grep -q '/metrics' "$curl_log"; then
  fail "metrics scraped when /health was down"
fi
run_health
assert_eq "$(restart_count)" 1 "fifth /health failure restarts"

# --- worker TCPStore port replaced: confirm, then restart, no chat wait ---
new_case
ready_old
export DSV41_TEST_CHAT_CODE=200
run_health
write_tcp 9C41
export DSV41_TEST_CHAT_CODE=timeout
run_health
assert_eq "$(restart_count)" 0 "first peer change restarted"
assert_eq "$(sed -n '1p' "$runtime/dsv41-cluster-health.peer")" "id=9C40" "baseline held on first change"
assert_eq "$(sed -n '2p' "$runtime/dsv41-cluster-health.peer")" "streak=1" "first change streak"
if grep -q chat/completions "$curl_log"; then
  fail "peer change waited on a chat probe"
fi
grep -q 'confirming 1/2' "$work/err"
run_health
assert_eq "$(restart_count)" 1 "second peer change restarts"
grep -q 'TCPStore peer changed' "$work/err"

# --- an additional socket on the same port is not a restart ---
new_case
ready_old
export DSV41_TEST_CHAT_CODE=200
run_health
write_tcp 9C40 9C41
run_health
assert_eq "$(restart_count)" 0 "extra socket restarted"
assert_eq "$(sed -n '1p' "$runtime/dsv41-cluster-health.peer")" "id=9C40,9C41" "baseline absorbed the extra socket"
if ! grep -q chat/completions "$curl_log"; then
  fail "extra socket skipped the chat probe"
fi

# --- a peer that returns to the saved port clears the streak ---
new_case
ready_old
export DSV41_TEST_CHAT_CODE=200
run_health
write_tcp 9C41
export DSV41_TEST_CHAT_CODE=timeout
run_health
write_tcp 9C40
export DSV41_TEST_CHAT_CODE=200
run_health
assert_eq "$(restart_count)" 0 "peer flap restarted"
assert_eq "$(sed -n '2p' "$runtime/dsv41-cluster-health.peer")" "streak=0" "flap cleared the streak"

# --- unreadable tcp and tcp6 tables do not arm or restart ---
new_case
ready_old
rm -f "$tcp" "$tcp6"
printf '%s\n' "not a table" >"$tcp"
printf '%s\n' "not a table" >"$tcp6"
chmod 000 "$tcp" "$tcp6"
export DSV41_TEST_CHAT_CODE=200
run_health
assert_eq "$rc" 0 "unreadable tcp rc"
assert_eq "$(restart_count)" 0 "unreadable tcp restarts"
if [ -e "$runtime/dsv41-cluster-health.peer" ]; then
  fail "unreadable tcp armed a baseline"
fi
chmod 644 "$tcp" "$tcp6" || true

# --- open exposure probes without a key file ---
new_case
sed -i 's/^DSV41_EXPOSE=aperture$/DSV41_EXPOSE=open/' "$envfile"
rm -f "$keyfile"
ready_old
export DSV41_TEST_CHAT_CODE=200
run_health
assert_eq "$rc" 0 "open mode rc"
assert_eq "$(restart_count)" 0 "open mode restarts"
if [ -f "$auth_log" ] && grep -q saw-auth "$auth_log"; then
  fail "open mode sent an Authorization header"
fi

# --- replacing the container clears the streak ---
new_case
ready_old
export DSV41_TEST_CHAT_CODE=200
run_health
printf '%s\n' 3 >"$runtime/dsv41-cluster-health.fails"
printf 'prompt=9\ngeneration=9\n' >"$runtime/dsv41-cluster-health.metrics"
bash "$script_dir/prepare.sh" docker-rm
if [ -e "$runtime/dsv41-cluster.ready" ] || [ -e "$runtime/dsv41-cluster-health.fails" ] || [ -e "$runtime/dsv41-cluster-health.peer" ] || [ -e "$runtime/dsv41-cluster-health.metrics" ]; then
  fail "docker-rm left watchdog state behind"
fi

# --- tcp4 still arms when tcp6 is absent ---
new_case
rm -f "$tcp6"
ready_old
export DSV41_TEST_CHAT_CODE=200
run_health
assert_eq "$rc" 0 "tcp6 absent rc"
assert_eq "$(sed -n '1p' "$runtime/dsv41-cluster-health.peer")" "id=9C40" "tcp4 baseline without tcp6"
assert_eq "$(restart_count)" 0 "tcp6 absent restarts"

# --- IPv4-mapped tcp6 socket is the worker, including lowercase hex ---
new_case
ready_old
write_tcp
write_tcp6 9C40
sed -i 's/0000000000000000FFFF00000B64A8C0/0000000000000000ffff00000b64a8c0/g' "$tcp6"
export DSV41_TEST_CHAT_CODE=200
run_health
assert_eq "$rc" 0 "tcp6 arm rc"
assert_eq "$(restart_count)" 0 "tcp6 arm restarts"
assert_eq "$(sed -n '1p' "$runtime/dsv41-cluster-health.peer")" "id=9C40" "tcp6 baseline port"
if grep -q chat/completions "$curl_log"; then
  :
else
  fail "tcp6 arm skipped the chat probe"
fi
# The same port moving from tcp6 to tcp4 is not a restart.
write_tcp 9C40
write_tcp6
run_health
assert_eq "$(restart_count)" 0 "tcp6 to tcp4 restarted"
assert_eq "$(sed -n '1p' "$runtime/dsv41-cluster-health.peer")" "id=9C40" "tcp4 kept the baseline"
if ! grep -q chat/completions "$curl_log"; then
  fail "tcp6 to tcp4 skipped the chat probe"
fi
write_tcp
write_tcp6 9C41
export DSV41_TEST_CHAT_CODE=timeout
run_health
assert_eq "$(restart_count)" 0 "first tcp6 peer change restarted"
assert_eq "$(sed -n '1p' "$runtime/dsv41-cluster-health.peer")" "id=9C40" "tcp6 baseline held"
assert_eq "$(sed -n '2p' "$runtime/dsv41-cluster-health.peer")" "streak=1" "tcp6 first change streak"
if grep -q chat/completions "$curl_log"; then
  fail "tcp6 peer change waited on a chat probe"
fi
grep -q 'confirming 1/2' "$work/err"
run_health
assert_eq "$(restart_count)" 1 "second tcp6 peer change restarts"
grep -q 'TCPStore peer changed' "$work/err"

# --- a long prefill: running > 0 and prompt tokens advancing is not a strike ---
# 8 timeouts stand in for the measured 146.6s TTFT (five would restart).
new_case
ready_old
export DSV41_TEST_CHAT_CODE=timeout
export DSV41_TEST_METRICS=advance-prompt
i=0
while [ "$i" -lt 8 ]; do
  run_health
  i=$((i + 1))
done
assert_eq "$rc" 0 "advancing prompt rc"
assert_eq "$(restart_count)" 0 "advancing prompt restarted"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 0 "advancing prompt streak"
grep -q 'token counters advanced' "$work/err"
grep -q saw-auth "$auth_log"
assert_clean_secret
prompt_now=$(sed -n 's/^prompt=//p' "$runtime/dsv41-cluster-health.metrics")
if [ "${prompt_now:-0}" -le 30000 ]; then
  fail "advancing prompt baseline did not move (${prompt_now:-missing})"
fi

# --- generation tokens advancing, prompt frozen, is the same veto ---
new_case
ready_old
export DSV41_TEST_CHAT_CODE=timeout
export DSV41_TEST_METRICS=advance-gen
i=0
while [ "$i" -lt 8 ]; do
  run_health
  i=$((i + 1))
done
assert_eq "$(restart_count)" 0 "advancing generation restarted"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 0 "advancing generation streak"
grep -q 'token counters advanced' "$work/err"
assert_clean_secret

# --- frozen counters: the first busy scrape arms, the next five restart ---
# 6 * 20s probes, plus up to one 15s tick, stays under 2.5 min.
new_case
ready_old
export DSV41_TEST_CHAT_CODE=timeout
export DSV41_TEST_METRICS=frozen
run_health
assert_eq "$(restart_count)" 0 "frozen baseline restarted"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 0 "frozen baseline is not a strike"
grep -q 'recording the token baseline' "$work/err"
assert_eq "$(sed -n 's/^prompt=//p' "$runtime/dsv41-cluster-health.metrics")" "1005" "frozen prompt sums every series"
i=0
while [ "$i" -lt 4 ]; do
  run_health
  i=$((i + 1))
done
assert_eq "$(restart_count)" 0 "four frozen samples restarted"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 4 "four frozen samples counted"
run_health
assert_eq "$(restart_count)" 1 "fifth frozen sample restarts"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 0 "frozen restart resets the streak"
if [ -e "$runtime/dsv41-cluster-health.metrics" ]; then
  fail "frozen restart left the metrics baseline in place"
fi
assert_clean_secret

# --- running == 0 counts immediately, even on the first scrape ---
new_case
ready_old
export DSV41_TEST_CHAT_CODE=timeout
export DSV41_TEST_METRICS=idle
run_health
assert_eq "$(restart_count)" 0 "idle metrics restarted"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 1 "idle metrics counted"
if grep -q 'recording the token baseline' "$work/err"; then
  fail "idle metrics was treated as a live prefill"
fi

# --- a counter reset records a new baseline and does not count ---
new_case
ready_old
export DSV41_TEST_CHAT_CODE=timeout
export DSV41_TEST_METRICS=drop
run_health
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 0 "drop baseline is not a strike"
run_health
assert_eq "$(restart_count)" 0 "counter reset restarted"
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 0 "counter reset counted"
grep -q 'went backwards' "$work/err"
assert_eq "$(sed -n 's/^prompt=//p' "$runtime/dsv41-cluster-health.metrics")" "15" "counter reset baseline"
run_health
assert_eq "$(cat "$runtime/dsv41-cluster-health.fails")" 1 "frozen after reset counted"

printf 'dsv41 health watchdog checks passed.\n'
