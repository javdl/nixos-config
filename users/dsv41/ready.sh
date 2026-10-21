#!/usr/bin/env bash
# Record head readiness without blocking the head unit.
#
# Poll GET /health (no API key) for about 20 minutes. A cold load is
# ~6.5 minutes plus pairing, which used to exceed a 10 minute budget.
# When /health answers, one authenticated GET /v1/models distinguishes a
# key mismatch (401) from a server that is still loading.
# The head starts this with --no-block. It is not part of the head's
# start job, so home-manager switch returns once the container is up.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
dsv41_source_cluster
dsv41_require_runtime

if [ "$DSV41_ROLE" != head ]; then
  exit 0
fi

flag=$(dsv41_ready_flag)
rm -f "$flag"

health_url="http://127.0.0.1:${DSV41_PORT}/health"
models_url="http://127.0.0.1:${DSV41_PORT}/v1/models"
cfg=$(mktemp "${XDG_RUNTIME_DIR}/dsv41-curl.XXXXXX")
chmod 600 "$cfg"
trap 'rm -f "$cfg"' EXIT
"$here/api-key.sh" append-auth "$cfg"

attempt=0
while [ "$attempt" -lt "$DSV41_READY_RETRIES" ]; do
  if "$(dsv41_curl)" --connect-timeout 5 --max-time 10 -sf -o /dev/null "$health_url"; then
    code=$("$(dsv41_curl)" --config "$cfg" --connect-timeout 5 --max-time 30 -s -o /dev/null -w '%{http_code}' "$models_url" || true)
    case "$code" in
      200)
        printf '%s\n' ready >"$flag"
        echo "dsv41 cluster: ready (127.0.0.1:${DSV41_PORT}/health, authenticated /v1/models)" >&2
        exit 0
        ;;
      401)
        dsv41_die "127.0.0.1:${DSV41_PORT}/v1/models returned 401. The API key was rejected. ~/.config/spark-vllm/api.env must be the Aperture provider key (quotes around the value are fine in that file). Fix the file, then: systemctl --user restart dsv41-cluster-head"
        ;;
    esac
    echo "dsv41 cluster: /health is up but /v1/models returned ${code:-none}; retrying" >&2
  fi
  attempt=$((attempt + 1))
  sleep "$DSV41_READY_RETRY_DELAY"
done

echo "dsv41 cluster: 127.0.0.1:${DSV41_PORT}/health was not ready after ${DSV41_READY_RETRIES} tries (about 20 min); restarting dsv41-cluster-head" >&2
"$(dsv41_systemctl)" --user restart --no-block dsv41-cluster-head || true
exit 1
