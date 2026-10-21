#!/usr/bin/env bash
# Block until the head answers /v1/models. Measured cold boot is 6m23s.
# Chat and /v1 routes send the API key in the default Aperture profile.
# /health does not use the key; this check does, because it is a /v1 route.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
dsv41_source_cluster
dsv41_require_runtime

if [ "$DSV41_ROLE" != head ]; then
  exit 0
fi

url="http://127.0.0.1:${DSV41_PORT}/v1/models"
cfg=$(mktemp "${XDG_RUNTIME_DIR}/dsv41-curl.XXXXXX")
chmod 600 "$cfg"
trap 'rm -f "$cfg"' EXIT
"$here/api-key.sh" append-auth "$cfg"

attempt=0
while [ "$attempt" -lt "$DSV41_READY_RETRIES" ]; do
  if "$(dsv41_curl)" --config "$cfg" --connect-timeout 5 --max-time 30 -sf -o /dev/null "$url"; then
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep "$DSV41_READY_RETRY_DELAY"
done
dsv41_die "127.0.0.1:${DSV41_PORT}/v1/models was not ready after ${DSV41_READY_RETRIES} tries"
