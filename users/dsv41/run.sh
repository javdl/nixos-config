#!/usr/bin/env bash
# Foreground `docker run --rm`. systemd Type=exec tracks this process.
# The HTTP bind address is not the NCCL rendezvous. Ranks pair on
# DSV41_MASTER_ADDR:DSV41_MASTER_PORT over the CX7.
set -euo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
dsv41_source_cluster
dsv41_require_runtime

gid_env="${DSV41_GID_ENV:-${XDG_RUNTIME_DIR}/dsv41-cluster-gid.env}"
api_env="${XDG_RUNTIME_DIR}/dsv41-cluster-api.env"
cache="${HOME:?}/${DSV41_CACHE_REL}"

if [ ! -f "$gid_env" ]; then
  dsv41_die "GID env file missing: ${gid_env}"
fi
if [ ! -f "$DSV41_SERVE_SCRIPT" ]; then
  dsv41_die "serve script missing: ${DSV41_SERVE_SCRIPT}"
fi
if [ ! -d "$cache" ]; then
  dsv41_die "cache directory missing: ${cache}"
fi

args=(
  "$(dsv41_docker)" run
  --rm
  --name "$DSV41_CONTAINER"
  --pull=never
  --network host
  --ipc host
  --shm-size "$DSV41_SHM"
  --gpus all
  --device /dev/infiniband
  --ulimit "memlock=${DSV41_MEMLOCK}"
  --ulimit "stack=${DSV41_STACK}"
  --security-opt label=disable
  --entrypoint /bin/bash
  --env-file "$DSV41_RECIPE_ENV"
  --env-file "$gid_env"
  -e "VLLM_HOST_IP=${DSV41_HOST_IP}"
  -e "DSV41_MODEL_DIR=${DSV41_MODEL_DIR}"
  -e "DSV41_SERVED=${DSV41_SERVED}"
  -e "DSV41_BIND=${DSV41_BIND}"
  -e "DSV41_PORT=${DSV41_PORT}"
  -e "DSV41_RANK=${DSV41_RANK}"
  -e "DSV41_MASTER_ADDR=${DSV41_MASTER_ADDR}"
  -e "DSV41_MASTER_PORT=${DSV41_MASTER_PORT}"
  -e "DSV41_TP=${DSV41_TP}"
  -e "DSV41_NNODES=${DSV41_NNODES}"
  -e "DSV41_UTIL=${DSV41_UTIL}"
  -e "DSV41_MAX_LEN=${DSV41_MAX_LEN}"
  -e "DSV41_MAX_SEQS=${DSV41_MAX_SEQS}"
  -e "DSV41_MAX_BATCH=${DSV41_MAX_BATCH}"
  -e "DSV41_LOAD_FORMAT=${DSV41_LOAD_FORMAT}"
  -e "DSV41_KV_BYTES=${DSV41_KV_BYTES}"
  -e "DSV41_ENGRAM=${DSV41_ENGRAM}"
  -e "DSV41_GRAPH=${DSV41_GRAPH}"
  -e "DSV41_KERNEL=${DSV41_KERNEL}"
  -e "DSV41_SPEC=${DSV41_SPEC}"
  -e "DSV41_MM=${DSV41_MM}"
)

if [ "$DSV41_EXPOSE" = aperture ] && [ "$DSV41_ROLE" = head ]; then
  if [ ! -f "$api_env" ]; then
    dsv41_die "API key env file was not prepared (${api_env})"
  fi
  args+=(--env-file "$api_env")
fi

args+=(
  -v "${DSV41_MODEL_DIR}:${DSV41_MODEL_DIR}:ro"
  -v "${DSV41_SERVE_SCRIPT}:/serve.sh:ro"
  -v "${cache}:/root/.cache"
  -v "${DSV41_MARKOV}:/root/.cache/markov_top_tokens.json:ro"
  "$DSV41_IMAGE"
  /serve.sh
)

exec "${args[@]}"
