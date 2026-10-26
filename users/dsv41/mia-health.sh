#!/usr/bin/env bash
# Log-only /health probe for the Mia unit.
#
# Never restarts dsv41-mia. A GPU fault should show up here and in the
# unit journal, then wait for a person. The unit's own Restart=on-failure
# is already capped (3 starts per 30 minutes) and this probe does not add
# another loop.
#
# Quiet during the startup grace: Type=simple is active as soon as
# start.sh is forked, and a warm load is a few minutes.
set -euo pipefail
set +x

unit=${MIA_UNIT:-dsv41-mia.service}
grace=${MIA_HEALTH_GRACE_SEC:-900}
url=${MIA_HEALTH_URL:-http://127.0.0.1:8000/health}
systemctl=${MIA_SYSTEMCTL_BIN:-/usr/bin/systemctl}
curl_bin=${MIA_CURL_BIN:-/usr/bin/curl}
date_bin=${MIA_DATE_BIN:-/usr/bin/date}

if ! "$systemctl" --user is-active --quiet "$unit"; then
  exit 0
fi

stamp=$("$systemctl" --user show --timestamp=unix -p ActiveEnterTimestampUSec --value "$unit" || true)
case "$stamp" in
  '' | n/a | 0) exit 0 ;;
esac

if printf '%s' "$stamp" | grep -Eq '^[0-9]+$'; then
  now_us=$("$date_bin" +%s%6N)
  age=$(((now_us - stamp) / 1000000))
else
  entered=$("$date_bin" -d "$stamp" +%s) || exit 0
  now=$("$date_bin" +%s)
  age=$((now - entered))
fi

if [ "$age" -lt "$grace" ]; then
  exit 0
fi

if "$curl_bin" --connect-timeout 5 --max-time 5 -sf -o /dev/null "$url"; then
  exit 0
fi

echo "dsv41 mia: ${url} did not answer and ${unit} has been active for ${age}s. Not restarting." >&2
exit 0
