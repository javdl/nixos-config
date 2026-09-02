# fu137 local inference, round 2 (2026-09-02)

Follow-up to [`fu137-local-inference.md`](fu137-local-inference.md) (round 1, 2026-08-29). Round 1 measured
1.5B / 33M / 88M-parameter models, which mostly measured kernel overhead. This round
fills the 24 GiB card with models that answer real workload questions.

Every step is logged below with a wall-clock timestamp as it starts and ends, so the
durations (downloads, loads, runs) are reproducible facts rather than estimates.

Harness: `scripts/fu137-gpu-bench.py` (extended this round with `--coder-model`,
`--embed-model`, `--vision-model`, `rerank`, `vlm` and `ollama` tiers).
Raw numbers: `docs/fu137-gpu-bench-round2.json`.

## Timeline

- `2026-09-02 06:21:18` **Step 0: system check.** GPU idle, 20 057 MiB VRAM free (desktop stack holds 4 064 MiB). RAM 30 GiB with only 6.8 GiB available; a Bitwarden desktop renderer (pid 3131, Electron 39) had leaked to 4.7 GB RSS over 6 days.
- `2026-09-02 06:21:18` **Step 0: closed Bitwarden desktop** (`kill -TERM 2008`). RAM available 6.8 -> 11 GiB. VRAM used 4 064 -> 3 886 MiB.

```
name, memory.total [MiB], memory.used [MiB], driver_version, temperature.gpu, power.draw [W]
NVIDIA GeForce RTX 3090, 24576 MiB, 3887 MiB, 610.57.04, 33, 17.42 W
               total        used        free      shared  buff/cache   available
Mem:              30          19           5           0           7          11
/dev/mapper/root  930G  147G  782G  16% /
tmpfs              16G  5.6G  9.8G  37% /tmp
```

- `2026-09-02 06:21:18` **Step 1: extend harness** (`scripts/fu137-gpu-bench.py`) with model flags, rerank/vlm/ollama tiers, merged JSON output.
- `2026-09-02 06:22:37` **Step 1 done.** Harness patched (+~180 lines): argparse model flags, `device_map=cuda` streaming loads (RAM is the tight resource), tiers `rerank` (bge-reranker-v2-m3, 512-tok pairs), `vlm` (Qwen2.5-VL-7B, 512px image -> 64 tokens), `ollama` (GGUF via HTTP API, throughput from ollama's own ns counters). Results merge into one JSON keyed `tier:model`.
- `2026-09-02 06:22:37` **Step 2: rebuild Python env** in scratchpad (`uv venv`, torch cu130 wheel + transformers + accelerate + pillow). Round-1 venv was deleted during cleanup.
- `2026-09-02 06:23:37` **Step 2 done** in 49 s (uv cache warm). torch 2.13.0+cu130, transformers 5.16.1, CUDA available.
- `2026-09-02 06:23:37` **Step 3: Qwen2.5-Coder-7B-Instruct fp16** via transformers. Download ~15.2 GB from HF, then the tier-3 protocol (prefill + 128-token decode at ctx 512/2048/8192). Started in background; download timed separately.
- `2026-09-02 06:27:30` Step 3 download done: 226 s for 15 GB (~66 MB/s), revision c03e6d3. Bench run starting.
- `2026-09-02 06:29:28` **Step 3 done.** Qwen2.5-Coder-7B fp16: load 11.3 s (device_map=cuda streamed 14.19 GiB straight to VRAM, no RAM spike), prefill 3.3-4.4k tok/s, **decode 47.4 tok/s** at ctx 512, 45.0 at ctx 8192 (17.0 GiB peak). Roofline for 14.19 GiB of weights at 846 GB/s is 55.5 tok/s, so HF generate hits **85 % of roofline** here versus 44 % on the 1.5B: per-step launch overhead is amortised once the weight read dominates.

```
  load: 11.3s   params: 7.616B   VRAM(weights): 14.186 GiB
  ctx=  512  prefill   156.46 ms (    3272 tok/s)  |  decode   47.4 tok/s (128 new)  VRAM 14.370 GiB
  ctx= 2048  prefill   467.88 ms (    4377 tok/s)  |  decode   46.9 tok/s (128 new)  VRAM 14.898 GiB
  ctx= 8192  prefill  1954.44 ms (    4191 tok/s)  |  decode   45.0 tok/s (128 new)  VRAM 17.007 GiB
```

- `2026-09-02 06:29:28` **Step 4: install ollama-cuda from pacman** (section A2 of round-1 doc). Checking sudo first.
- `2026-09-02 06:29:47` Step 4 blocked: `sudo -n true` -> "a password is required". Deferred to the end; Joost runs the pacman command from a terminal. Continuing with the no-install tiers.
- `2026-09-02 06:29:47` **Step 5: embeddings + rerank + vision encoders.** bge-m3 (seq 512), bge-reranker-v2-m3 (512-tok pairs), SigLIP2 so400m-patch16-384 image tower at 384 px. All fp16, downloads included in the timing.
- `2026-09-02 06:34:27` **Step 5 done** in 263 s (three downloads ~6.5 GB included). bge-m3 at seq 512: 180 docs/s = 92k tok/s, saturating at bs 32. bge-reranker-v2-m3: 181 pairs/s, numerically identical to bge-m3 (same XLM-R-large backbone, both compute-bound: 92k tok/s x ~0.67 GFLOP/tok = 62 TFLOP/s, near the fp16 tensor-core roofline). SigLIP2 so400m @384px: 107 img/s, saturated at bs 32; 2.1 GiB load figure includes the text tower, freed before the timed runs (0.82 GiB).

```
=== TIER 2: embeddings (BAAI/bge-m3, seq 512) ===
  load: 32.9s   VRAM(weights): 1.058 GiB
  bs=   1 seq=512      8.56 ms      116.8 docs/s        59804 tok/s  VRAM 1.077 GiB
  bs=   8 seq=512     49.80 ms      160.7 docs/s        82254 tok/s  VRAM 1.154 GiB
  bs=  32 seq=512    179.50 ms      178.3 docs/s        91274 tok/s  VRAM 1.417 GiB
  bs= 128 seq=512    705.97 ms      181.3 docs/s        92831 tok/s  VRAM 2.473 GiB
  bs= 256 seq=512   1422.89 ms      179.9 docs/s        92117 tok/s  VRAM 3.880 GiB
=== TIER 2b: rerank (BAAI/bge-reranker-v2-m3) ===
  load: 31.1s   VRAM(weights): 1.066 GiB
  bs=   1 seq=512      8.35 ms     119.8 pairs/s  VRAM 1.077 GiB
  bs=   8 seq=512     50.01 ms     160.0 pairs/s  VRAM 1.154 GiB
  bs=  32 seq=512    179.21 ms     178.6 pairs/s  VRAM 1.417 GiB
  bs= 128 seq=512    707.30 ms     181.0 pairs/s  VRAM 2.473 GiB
=== TIER 4: vision encode (google/siglip2-so400m-patch16-384, 384px) ===
  load: 75.8s   VRAM(weights): 2.125 GiB
  bs=   1 384x384     11.86 ms       84.3 img/s  VRAM 0.822 GiB
  bs=   8 384x384     79.63 ms      100.5 img/s  VRAM 0.926 GiB
  bs=  32 384x384    298.42 ms      107.2 img/s  VRAM 1.287 GiB
  bs= 128 384x384   1198.93 ms      106.8 img/s  VRAM 2.728 GiB
  bs= 256 384x384   2489.94 ms      102.8 img/s  VRAM 4.647 GiB
```

- `2026-09-02 06:34:27` **Step 6: Qwen2.5-VL-7B-Instruct fp16** (vision-language). ~16.6 GB download, then 512px image + fixed garment-description prompt, 64 new tokens, bs 1 and 4. Background job.
- `2026-09-02 06:35:00` Step 6 first attempt failed in 6 s: `Qwen2VLVideoProcessor requires the Torchvision library`. Added torchvision to the venv, re-running.
- `2026-09-02 06:39:51` **Step 6 done** in 274 s total (load 255 s = 16.6 GB download + weight stream; 8.29 B params, 15.45 GiB VRAM). Qwen2.5-VL-7B fp16, 512px image + garment prompt, 64 new tokens: **bs 1 = 39.9 img/min (42.6 tok/s), bs 4 = 127 img/min (136 tok/s)** at 15.8 GiB. Decode is memory-bound so batching 4 images costs only 25 % more wall time. Stale `vlm:error` key from the torchvision attempt removed from the JSON.

```
  load: 255.2s   params: 8.292B   VRAM(weights): 15.445 GiB
  bs= 1 512px in_tok=362      1502 ms     39.9 img/min    42.6 tok/s  VRAM 15.530 GiB
  bs= 4 512px in_tok=362      1887 ms    127.2 img/min   135.7 tok/s  VRAM 15.761 GiB
```

- `2026-09-02 06:39:51` **Waiting on Step 4/7**: ollama-cuda install needs sudo from Joost's terminal.
- `2026-09-02 15:01:52` **Step 4 done** (by Joost, from a terminal): `ollama-cuda 0.32.15-1` installed, `ollama.service` active. Journal: `inference compute ... library=CUDA compute=8.6 ... total=23.6 GiB available=20.3 GiB`. Models dir /var/lib/ollama, flash attention off by default.
- `2026-09-02 15:01:52` **Step 7: ollama GGUF pair.** ollama-cuda 0.32.15-1, active. Pulling qwen3-coder:30b (MoE, 3.3B active, Q4_K_M ~18.6 GB) and gpt-oss:20b (MoE, MXFP4 ~13 GB).
- `2026-09-02 15:09:04` pulled `qwen3-coder:30b` rc=0 in 431 s: 18 GB
- `2026-09-02 15:13:22` pulled `gpt-oss:20b` rc=0 in 258 s: 13 GB

```
NAME               ID              SIZE     MODIFIED               
gpt-oss:20b        17052f91a42e    13 GB    Less than a second ago    
qwen3-coder:30b    06c1097efce0    18 GB    4 minutes ago             
```

- `2026-09-02 15:13:22` ollama bench `qwen3-coder:30b` start

```
=== TIER 3b: ollama (qwen3-coder:30b) ===
  load: 26.5s   VRAM(delta): 19.697 GiB
  ctx=  380  prefill    70162 tok/s  |  decode  188.4 tok/s (128 new)  VRAM 19.160 GiB
  ctx= 1506  prefill   179907 tok/s  |  decode  184.8 tok/s (128 new)  VRAM 19.177 GiB
  ctx= 6002  prefill   918439 tok/s  |  decode  167.1 tok/s (128 new)  VRAM 19.012 GiB
```

- `2026-09-02 15:14:18` ollama bench `qwen3-coder:30b` done
- `2026-09-02 15:14:18` ollama bench `gpt-oss:20b` start

```
=== TIER 3b: ollama (gpt-oss:20b) ===
  load: 7.3s   VRAM(delta): 13.112 GiB
  ctx=  439  prefill    55109 tok/s  |  decode  158.1 tok/s (128 new)  VRAM 12.652 GiB
  ctx= 1565  prefill     7708 tok/s  |  decode  160.8 tok/s (128 new)  VRAM 12.636 GiB
  ctx= 6061  prefill   732182 tok/s  |  decode  154.4 tok/s (128 new)  VRAM 12.574 GiB
```

- `2026-09-02 15:14:43` ollama bench `gpt-oss:20b` done
- `2026-09-02 15:14:55` **Step 7 first pass done** (decode numbers valid, prefill invalid): the harness took best-of-3 while ollama served repeats 2-3 from its prefix KV cache, so `prompt_eval_duration` was near zero ("918k tok/s"). Patched the ollama tier to prepend a unique nonce line per request; re-running both models. Prompt sizing also corrected (filler is 3.0 chars/token, not 3.0 chars per 1).
- `2026-09-02 15:14:55` Step 7 re-run `qwen3-coder:30b` start

```
=== TIER 3b: ollama (qwen3-coder:30b) ===
  load: 23.1s   VRAM(delta): 19.442 GiB
  ctx=  550  prefill     3460 tok/s  |  decode  193.0 tok/s (128 new)  VRAM 18.920 GiB
  ctx= 2085  prefill     4311 tok/s  |  decode  183.1 tok/s (128 new)  VRAM 18.920 GiB
  ctx= 8231  prefill     4048 tok/s  |  decode  161.3 tok/s (128 new)  VRAM 18.916 GiB
```

- `2026-09-02 15:15:56` Step 7 re-run `qwen3-coder:30b` done
- `2026-09-02 15:15:56` Step 7 re-run `gpt-oss:20b` start

```
=== TIER 3b: ollama (gpt-oss:20b) ===
  load: 6.7s   VRAM(delta): 13.083 GiB
  ctx=  595  prefill     5117 tok/s  |  decode  164.9 tok/s (128 new)  VRAM 12.679 GiB
  ctx= 2130  prefill     5978 tok/s  |  decode  159.4 tok/s (128 new)  VRAM 12.685 GiB
  ctx= 8276  prefill     6378 tok/s  |  decode  155.3 tok/s (128 new)  VRAM 12.685 GiB
```

- `2026-09-02 15:16:25` Step 7 re-run `gpt-oss:20b` done
- `2026-09-02 15:17:08` **Step 7 done.** qwen3-coder:30b (Q4_K_M, 3.3 B active): load 23 s, **193 tok/s decode** at ctx 550, 161 at ctx 8k, prefill 3.5-4.3k tok/s, 19.4 GiB. gpt-oss:20b (MXFP4, 3.6 B active): load 6.7 s, **165 tok/s**, 155 at ctx 8k, prefill 5-6.4k tok/s, 13.1 GiB.
- `2026-09-02 15:17:08` **Step 8: write results + recommendation, commit, push.**

## Results

All fp16 unless noted. Decode = new tokens per second after prefill, best of N.
Roofline = weight bytes read per token / 846 GB/s (measured in round 1).

### Coding models

| Model | Runtime | Weights | ctx 512 decode | ctx 8k decode | Prefill tok/s | Peak VRAM | Load |
|---|---|---|---|---|---|---|---|
| Qwen2.5-Coder-1.5B (round 1) | HF fp16 | 2.9 GiB | 121 tok/s | 108 | 12-16k | 4.9 GiB | 4 s |
| **Qwen2.5-Coder-7B-Instruct** | HF fp16 | 14.2 GiB | **47.4 tok/s** | 45.0 | 3.3-4.4k | 17.0 GiB | 11 s |
| **qwen3-coder:30b** (30B-A3B) | ollama Q4_K_M | 18.6 GB | **193 tok/s** | 161 | 3.5-4.3k | 19.4 GiB | 23 s |
| **gpt-oss:20b** (20B-A3.6B) | ollama MXFP4 | 13 GB | **165 tok/s** | 155 | 5.1-6.4k | 13.1 GiB | 7 s |

The 7B fp16 reaches 85 % of its 55.5 tok/s roofline (round 1's 1.5B managed 44 %):
once the weight read dominates, HF `generate` stops being the bottleneck. The two MoE
models decode 3.5-4x faster than the dense 7B while carrying 20-30 B parameters,
because only the ~3 B active parameters are read per token. qwen3-coder:30b uses 19.4
of the 20.3 GiB ollama can see; it fits only because the Bitwarden leak was closed and
nothing else large is on the GPU.

### Embeddings and rerank

| Model | seq | Peak throughput | Saturates at | VRAM |
|---|---|---|---|---|
| bge-small-en-v1.5 (round 1) | 128 | 7 383 docs/s (945k tok/s) | bs 256 | 0.33 GiB |
| **bge-m3** (568 M, multilingual) | 512 | **181 docs/s (93k tok/s)** | bs 32 | 2.5 GiB @ bs 128 |
| **bge-reranker-v2-m3** | 512 pairs | **181 pairs/s** | bs 32 | 2.5 GiB @ bs 128 |

bge-m3 and the reranker share the XLM-R-large backbone and produce identical numbers,
which is the signature of a compute-bound workload: 93k tok/s x ~0.67 GFLOP/token is
~62 TFLOP/s, close to the fp16 tensor-core roofline. A retrieve-then-rerank pipeline
on this card handles ~180 candidate pairs per second per query stream.

### Vision

| Model | Task | Input | Throughput | VRAM |
|---|---|---|---|---|
| CLIP ViT-B/32 (round 1) | image embedding | 224 px | 5 126 img/s | 0.55 GiB |
| **SigLIP2 so400m-patch16** | image embedding | 384 px | **107 img/s** | 1.3 GiB @ bs 32 |
| **Qwen2.5-VL-7B-Instruct** | image -> 64-token description | 512 px | **40 img/min** (bs 1), **127 img/min** (bs 4) | 15.8 GiB |

SigLIP2 at 384 px costs ~48x CLIP-B/32 at 224 px (400 M params, 576 patches vs 50)
and is the realistic number for a product-image similarity index: ~385k images/hour.
The VLM decodes at 43 tok/s single-stream and 136 tok/s at batch 4; a catalogue of
10k product photos gets a structured description in ~80 minutes at bs 4.

## What the numbers say

1. **Run coding models through ollama, as MoE, quantised.** qwen3-coder:30b at 193
   tok/s is the best quality-per-second on this card and the obvious backend for
   local agent loops. gpt-oss:20b is the fallback when 6 GiB must stay free for
   something else (a VLM, a big embedding batch, a browser).
2. **fp16 dense 7B via transformers is a research path, not a serving path.** 47 tok/s
   is roofline-bound; the same model as Q4_K_M in ollama would decode ~2.5x faster.
3. **Embeddings/rerank are compute-bound and cheap on VRAM** (2.5 GiB at bs 128).
   They coexist with gpt-oss:20b (13.1 GiB) but not with qwen3-coder:30b (19.4 GiB).
4. **The VLM is the VRAM hog.** Qwen2.5-VL-7B fp16 needs 15.8 GiB and cannot share
   the card with either ollama coder. If vision + coding must run together, use
   `qwen2.5vl:7b` from ollama (Q4, ~6 GB) or a 3B VLM.
5. **RAM was the hidden constraint.** Closing one leaked Electron renderer freed 4.7
   GB; `device_map="cuda"` streaming kept every load off RAM, which is why a 16.6 GB
   model loaded in 11 s on a box with 10 GiB available.

## Recommended next workload

Wire **qwen3-coder:30b** into the agent tooling already on this box (aichat, Claude
Code router, pi/omp) and measure real task throughput: tokens per accepted edit, not
tokens per second. That is the number that decides whether local inference replaces
API calls for the routine loops, and it needs a day of normal use rather than a
harness.

Second candidate: a SigLIP2 + bge-m3 dual index over the FashionUnited image and
article corpus. Both models are small, fast, and multilingual, and the numbers above
put a full re-index of ~400k items in a few hours on this card.

## Disk after this round

| Path | Size | Contents |
|---|---|---|
| `~/.cache/huggingface/hub` | ~40 GB | Qwen2.5-Coder-7B, Qwen2.5-VL-7B, bge-m3, reranker, SigLIP2 |
| `/var/lib/ollama` | ~31 GB | qwen3-coder:30b, gpt-oss:20b |

Both caches are on the 930 GB root disk (782 GB free before this round).

## Reproduce

```bash
S=$(mktemp -d); cd $S
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python torch torchvision transformers accelerate pillow numpy sentencepiece protobuf
B=~/nixos-config/scripts/fu137-gpu-bench.py; OUT=results.json
.venv/bin/python $B coder --coder-model Qwen/Qwen2.5-Coder-7B-Instruct --out $OUT
.venv/bin/python $B embed rerank vision --embed-model BAAI/bge-m3 --embed-seq 512 \
  --vision-model google/siglip2-so400m-patch16-384 --vision-res 384 --out $OUT
.venv/bin/python $B vlm --out $OUT
sudo pacman -S --needed ollama-cuda && sudo systemctl enable --now ollama
ollama pull qwen3-coder:30b && ollama pull gpt-oss:20b
for m in qwen3-coder:30b gpt-oss:20b; do .venv/bin/python $B ollama --ollama-model $m --out $OUT; done
```
