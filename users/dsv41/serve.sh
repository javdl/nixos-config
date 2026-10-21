#!/usr/bin/env bash
# vLLM entrypoint for one rank of the dsv41 cluster.
# Values come from users/dsv41-cluster.nix via `docker run -e`.
# --master-addr/--master-port are the CX7 rendezvous. --host/--port are
# the HTTP listener and are not used to pair the ranks.
set -euo pipefail

: "${DSV41_MODEL_DIR:?}"
: "${DSV41_SERVED:?}"
: "${DSV41_BIND:?}"
: "${DSV41_PORT:?}"
: "${DSV41_RANK:?}"
: "${DSV41_MASTER_ADDR:?}"
: "${DSV41_MASTER_PORT:?}"
: "${DSV41_TP:?}"
: "${DSV41_NNODES:?}"
: "${DSV41_UTIL:?}"
: "${DSV41_MAX_LEN:?}"
: "${DSV41_MAX_SEQS:?}"
: "${DSV41_MAX_BATCH:?}"
: "${DSV41_LOAD_FORMAT:?}"
: "${DSV41_ENGRAM:?}"
: "${DSV41_GRAPH:?}"
: "${DSV41_KERNEL:?}"
: "${DSV41_SPEC:?}"
: "${DSV41_KV_BYTES:?}"
: "${DSV41_MM:?}"

args=(
  vllm serve "$DSV41_MODEL_DIR"
  --served-model-name "$DSV41_SERVED"
  --host "$DSV41_BIND"
  --port "$DSV41_PORT"
  --tensor-parallel-size "$DSV41_TP"
  --nnodes "$DSV41_NNODES"
  --node-rank "$DSV41_RANK"
  --master-addr "$DSV41_MASTER_ADDR"
  --master-port "$DSV41_MASTER_PORT"
  --gpu-memory-utilization "$DSV41_UTIL"
  --max-model-len "$DSV41_MAX_LEN"
  --max-num-seqs "$DSV41_MAX_SEQS"
  --max-num-batched-tokens "$DSV41_MAX_BATCH"
  --load-format "$DSV41_LOAD_FORMAT"
  --engram-config "$DSV41_ENGRAM"
  --compilation-config "$DSV41_GRAPH"
  --kernel-config "$DSV41_KERNEL"
  --enable-auto-tool-choice
  --tool-call-parser deepseek_v41
  --reasoning-parser deepseek_v41
  --speculative-config "$DSV41_SPEC"
  --kv-cache-memory-bytes "$DSV41_KV_BYTES"
  --limit-mm-per-prompt "$DSV41_MM"
)

if [ -n "${VLLM_API_KEY:-}" ]; then
  args+=(--api-key "$VLLM_API_KEY")
fi
if [ "$DSV41_RANK" != 0 ]; then
  args+=(--headless)
fi

exec "${args[@]}"
