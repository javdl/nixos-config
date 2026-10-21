#!/usr/bin/env bash
# Read VLLM_API_KEY from the host env file. The value is never printed.
# write-env: validate and write a docker env-file under $XDG_RUNTIME_DIR.
# append-auth: append a curl config Authorization header to the given file.
set -euo pipefail
set +x

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

dsv41_api_key_reject() {
  local val=$1
  case "$val" in
    *$'\n'* | *$'\r'* | *'"'* | *$'\\'*)
      dsv41_die "VLLM_API_KEY contains a newline, quote, or backslash"
      ;;
  esac
}

# Prints the key on stdout. Callers must not log it.
dsv41_api_key_value() {
  set +x
  local file=$1 line val mode owner
  if [ ! -e "$file" ]; then
    dsv41_die "API key file ${file} is missing. Create it mode 600 with one VLLM_API_KEY= line (the Aperture provider key) before switching"
  fi
  if [ -L "$file" ]; then
    dsv41_die "API key file ${file} must be a regular file, not a symlink"
  fi
  if [ ! -f "$file" ]; then
    dsv41_die "API key file ${file} is not a regular file"
  fi
  mode=$(stat -c '%a' "$file")
  case "$mode" in
    600 | 400) ;;
    *) dsv41_die "API key file ${file} must be mode 600 (got ${mode})" ;;
  esac
  owner=$(stat -c '%u' "$file")
  if [ "$owner" != "$(id -u)" ]; then
    dsv41_die "API key file ${file} must be owned by the user running the cluster"
  fi
  line=$(grep -E '^[[:space:]]*(export[[:space:]]+)?VLLM_API_KEY=' "$file" | head -n 1 || true)
  if [ -z "$line" ]; then
    dsv41_die "${file} has no VLLM_API_KEY= line"
  fi
  val=${line#*=}
  val=${val%$'\r'}
  val=${val%"${val##*[![:space:]]}"}
  val=${val#"${val%%[![:space:]]*}"}
  # One surrounding pair is file syntax, not part of the key. Both
  # VLLM_API_KEY=secret and VLLM_API_KEY="secret" (or single quotes) work.
  # A quote that remains after that strip is rejected below.
  if [ "${#val}" -ge 2 ] && [ "${val#\"}" != "$val" ] && [ "${val%\"}" != "$val" ]; then
    val=${val#\"}
    val=${val%\"}
  elif [ "${#val}" -ge 2 ] && [ "${val#\'}" != "$val" ] && [ "${val%\'}" != "$val" ]; then
    val=${val#\'}
    val=${val%\'}
  fi
  val=${val%"${val##*[![:space:]]}"}
  val=${val#"${val%%[![:space:]]*}"}
  if [ -z "$val" ]; then
    dsv41_die "VLLM_API_KEY in ${file} is empty"
  fi
  dsv41_api_key_reject "$val"
  printf '%s' "$val"
}

dsv41_source_cluster
dsv41_require_runtime

cmd=${1:-}
runtime_env="${XDG_RUNTIME_DIR}/dsv41-cluster-api.env"

case "$cmd" in
  write-env)
    if [ "${DSV41_EXPOSE}" != aperture ] || [ "${DSV41_ROLE}" != head ]; then
      rm -f "$runtime_env"
      exit 0
    fi
    val=$(dsv41_api_key_value "${DSV41_API_KEY_FILE:?}")
    umask 077
    # Docker --env-file keeps quote characters as part of the value
    # (verified on Docker 29.6.2). A quoted value becomes the vLLM key,
    # and every request 401s.
    printf 'VLLM_API_KEY=%s\n' "$val" >"$runtime_env"
    unset val
    ;;
  append-auth)
    dest=${2:?}
    if [ "${DSV41_EXPOSE}" != aperture ]; then
      exit 0
    fi
    val=$(dsv41_api_key_value "${DSV41_API_KEY_FILE:?}")
    umask 077
    printf 'header = "Authorization: Bearer %s"\n' "$val" >>"$dest"
    unset val
    ;;
  *)
    dsv41_die "usage: api-key.sh write-env|append-auth DEST"
    ;;
esac
