#!/usr/bin/env bash
# RoCE v2 GID index whose IPv4-mapped GID is this node's fabric address.
# Same rule as sudoingX/dgx-spark-deepseek-v41 scripts/launch/dsv41_tp2.sh
# gid_of at cc59c360: scan indexes 0..15, type contains "v2", GID contains
# ffff:<ipv4-hi>:<ipv4-lo>. The cluster attrset's gid is the fallback when
# sysfs has no match (journal warning); a detected index always wins.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
dsv41_source_cluster

fab_if=${DSV41_FAB_IF:?}
fab_hca=${DSV41_FAB_HCA:?}
declared=${DSV41_GID:?}
sysfs=${DSV41_SYSFS:-/sys}
if [ "${DSV41_GID_ENV:-}" = "-" ]; then
  out=""
elif [ -n "${DSV41_GID_ENV:-}" ]; then
  out=$DSV41_GID_ENV
else
  dsv41_require_runtime
  out="${XDG_RUNTIME_DIR}/dsv41-cluster-gid.env"
fi

ip_bin=$(dsv41_ip)
want=$("$ip_bin" -4 -o addr show "$fab_if" | awk '{print $4}' | cut -d/ -f1)
if [ -z "$want" ]; then
  dsv41_die "no IPv4 on ${fab_if}"
fi

# shellcheck disable=SC2046
hex=$(printf '%02x%02x%02x%02x' $(printf '%s' "$want" | tr '.' ' '))
prefix="${hex:0:4}:${hex:4:4}"
gid_dir="$sysfs/class/infiniband/$fab_hca/ports/1"
found=""
i=0
while [ "$i" -le 15 ]; do
  t=$(cat "$gid_dir/gid_attrs/types/$i" 2>/dev/null || true)
  g=$(cat "$gid_dir/gids/$i" 2>/dev/null || true)
  t=$(printf '%s' "$t" | tr 'A-Z' 'a-z')
  g=$(printf '%s' "$g" | tr 'A-F' 'a-f')
  case "$t" in
    *v2*) ;;
    *)
      i=$((i + 1))
      continue
      ;;
  esac
  case "$g" in
    *ffff:"$prefix"*)
      found=$i
      break
      ;;
  esac
  i=$((i + 1))
done

if [ -z "$found" ]; then
  echo "dsv41 cluster: no RoCE v2 GID for ${want} on ${fab_hca}; using declared index ${declared}" >&2
  found=$declared
elif [ "$found" != "$declared" ]; then
  echo "dsv41 cluster: detected NCCL_IB_GID_INDEX=${found} (cluster declares ${declared} for this node)" >&2
fi

case "$found" in
  ''|*[!0-9]*) dsv41_die "GID index is not an integer: ${found}" ;;
esac

line="NCCL_IB_GID_INDEX=${found}"
if [ -n "$out" ]; then
  umask 077
  printf '%s\n' "$line" >"$out"
else
  printf '%s\n' "$line"
fi
