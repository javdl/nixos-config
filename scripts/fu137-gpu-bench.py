#!/usr/bin/env python3
"""fu137 GPU benchmark: roofline, embeddings, coding-model inference, vision.

Reproducible: pinned model revisions, fixed seeds, fixed corpora, warmup +
timed repeats, VRAM measured with torch.cuda.max_memory_allocated over a reset
baseline so the desktop's ~1.7 GiB is excluded.

Usage: python bench.py [roofline] [embed] [coder] [vision]   (default: all)
"""
import gc, json, os, statistics, sys, time
import torch

torch.manual_seed(0)
DEV = "cuda"
RESULTS = {}


def sync():
    torch.cuda.synchronize()


def vram_reset():
    gc.collect()
    torch.cuda.empty_cache()
    torch.cuda.reset_peak_memory_stats()


def vram_peak_gib():
    return torch.cuda.max_memory_allocated() / 2**30


def timeit(fn, warmup=3, iters=10):
    """Return (median_s, min_s) over `iters` timed runs after `warmup`."""
    for _ in range(warmup):
        fn()
    sync()
    ts = []
    for _ in range(iters):
        t0 = time.perf_counter()
        fn()
        sync()
        ts.append(time.perf_counter() - t0)
    return statistics.median(ts), min(ts)


def gpu_state():
    import subprocess
    q = "clocks.sm,temperature.gpu,power.draw,utilization.gpu"
    out = subprocess.run(
        ["nvidia-smi", f"--query-gpu={q}", "--format=csv,noheader,nounits"],
        capture_output=True, text=True).stdout.strip()
    k = ["sm_clock_mhz", "temp_c", "power_w", "util_pct"]
    return dict(zip(k, [v.strip() for v in out.split(",")]))


# ---------------------------------------------------------------- roofline
def bench_roofline():
    print("\n=== TIER 1: roofline (GEMM + memory bandwidth) ===")
    out = {"gemm": [], "bandwidth": []}

    # GEMM: square matmul, FLOPs = 2*N^3
    for dtype, tf32, label in [
        (torch.float32, False, "fp32 (tf32 off)"),
        (torch.float32, True, "fp32 (tf32 on)"),
        (torch.float16, False, "fp16 tensor-core"),
        (torch.bfloat16, False, "bf16 tensor-core"),
    ]:
        torch.backends.cuda.matmul.allow_tf32 = tf32
        torch.backends.cudnn.allow_tf32 = tf32
        N = 8192
        a = torch.randn(N, N, device=DEV, dtype=dtype)
        b = torch.randn(N, N, device=DEV, dtype=dtype)
        med, best = timeit(lambda: a @ b, warmup=5, iters=20)
        tflops = 2 * N**3 / best / 1e12
        print(f"  {label:22s} N={N}  {best*1e3:7.2f} ms  ->  {tflops:7.2f} TFLOP/s")
        out["gemm"].append({"dtype": label, "N": N, "best_ms": best * 1e3,
                            "median_ms": med * 1e3, "tflops": tflops})
        del a, b
        vram_reset()
    torch.backends.cuda.matmul.allow_tf32 = False

    # Bandwidth: large elementwise copy, 2 bytes moved per element per direction
    for nbytes_gib in [1, 4]:
        n = int(nbytes_gib * 2**30 // 2)  # fp16 elements
        src = torch.empty(n, device=DEV, dtype=torch.float16)
        dst = torch.empty_like(src)
        med, best = timeit(lambda: dst.copy_(src), warmup=5, iters=20)
        gbs = (2 * n * 2) / best / 1e9  # read + write
        print(f"  device-copy {nbytes_gib} GiB       {best*1e3:7.2f} ms  ->  {gbs:7.1f} GB/s")
        out["bandwidth"].append({"size_gib": nbytes_gib, "best_ms": best * 1e3,
                                 "gb_per_s": gbs})
        del src, dst
        vram_reset()

    out["gpu_state_after"] = gpu_state()
    print(f"  GPU after roofline: {out['gpu_state_after']}")
    RESULTS["roofline"] = out


# -------------------------------------------------------------- embeddings
EMBED_MODEL = "BAAI/bge-small-en-v1.5"
EMBED_REV = "main"

def bench_embed():
    from transformers import AutoTokenizer, AutoModel
    print(f"\n=== TIER 2: embeddings ({EMBED_MODEL}) ===")
    vram_reset()
    t0 = time.perf_counter()
    tok = AutoTokenizer.from_pretrained(EMBED_MODEL, revision=EMBED_REV)
    model = AutoModel.from_pretrained(EMBED_MODEL, revision=EMBED_REV,
                                      dtype=torch.float16).to(DEV).eval()
    load_s = time.perf_counter() - t0
    print(f"  load: {load_s:.1f}s   VRAM(weights): {vram_peak_gib():.3f} GiB")

    # Fixed synthetic corpus: code-comment-like sentences, deterministic.
    base = ("def process_batch(items, timeout=30): return [transform(i) for i in items] "
            "# handles retry and backoff for the ingestion pipeline stage ")
    corpus = [(base * 3)[: 200 + (i * 37) % 400] for i in range(2048)]

    rows = []
    for bs in [1, 8, 32, 128, 256]:
        vram_reset()
        batch = corpus[:bs]
        enc = tok(batch, padding="max_length", truncation=True, max_length=128,
                  return_tensors="pt").to(DEV)
        ntok = int(enc["attention_mask"].numel())

        def run():
            with torch.inference_mode():
                o = model(**enc).last_hidden_state
                m = enc["attention_mask"].unsqueeze(-1)
                return (o * m).sum(1) / m.sum(1)

        med, best = timeit(run, warmup=3, iters=15)
        dps = bs / best
        tps = ntok / best
        print(f"  bs={bs:4d} seq=128  {best*1e3:8.2f} ms  {dps:9.1f} docs/s  "
              f"{tps:11.0f} tok/s  VRAM {vram_peak_gib():.3f} GiB")
        rows.append({"batch": bs, "seq_len": 128, "best_ms": best * 1e3,
                     "median_ms": med * 1e3, "docs_per_s": dps,
                     "tokens_per_s": tps, "vram_gib": vram_peak_gib()})

    RESULTS["embeddings"] = {"model": EMBED_MODEL, "dtype": "fp16",
                             "load_s": load_s, "runs": rows,
                             "gpu_state_after": gpu_state()}
    del model
    vram_reset()


# ------------------------------------------------------------ coding model
CODER_MODEL = "Qwen/Qwen2.5-Coder-1.5B-Instruct"

def bench_coder():
    from transformers import AutoTokenizer, AutoModelForCausalLM
    print(f"\n=== TIER 3: coding-model inference ({CODER_MODEL}) ===")
    vram_reset()
    t0 = time.perf_counter()
    tok = AutoTokenizer.from_pretrained(CODER_MODEL)
    model = AutoModelForCausalLM.from_pretrained(
        CODER_MODEL, dtype=torch.float16).to(DEV).eval()
    load_s = time.perf_counter() - t0
    w_gib = vram_peak_gib()
    nparams = sum(p.numel() for p in model.parameters())
    print(f"  load: {load_s:.1f}s   params: {nparams/1e9:.3f}B   "
          f"VRAM(weights): {w_gib:.3f} GiB")

    filler = "# utility helpers for the data ingestion service\n" \
             "def normalize(record):\n    return {k: v for k, v in record.items() if v}\n\n"
    rows = []
    for ctx in [512, 2048, 8192]:
        vram_reset()
        prompt = filler * (ctx // 20 + 40)
        ids = tok(prompt, return_tensors="pt").input_ids[:, :ctx].to(DEV)
        actual_ctx = ids.shape[1]

        # --- prefill: forward pass only, no generation
        def prefill():
            with torch.inference_mode():
                model(ids)

        p_med, p_best = timeit(prefill, warmup=2, iters=8)
        prefill_tps = actual_ctx / p_best

        # --- decode: generate NEW tokens, subtract prefill cost
        NEW = 128
        def decode():
            with torch.inference_mode():
                model.generate(ids, max_new_tokens=NEW, min_new_tokens=NEW,
                               do_sample=False, use_cache=True,
                               pad_token_id=tok.eos_token_id)

        d_med, d_best = timeit(decode, warmup=1, iters=5)
        decode_tps = NEW / (d_best - p_best)
        print(f"  ctx={actual_ctx:5d}  prefill {p_best*1e3:8.2f} ms "
              f"({prefill_tps:8.0f} tok/s)  |  decode {decode_tps:6.1f} tok/s "
              f"({NEW} new)  VRAM {vram_peak_gib():.3f} GiB")
        rows.append({"ctx": actual_ctx, "prefill_ms": p_best * 1e3,
                     "prefill_tok_per_s": prefill_tps, "new_tokens": NEW,
                     "decode_total_ms": d_best * 1e3,
                     "decode_tok_per_s": decode_tps,
                     "vram_gib": vram_peak_gib()})

    RESULTS["coder"] = {"model": CODER_MODEL, "dtype": "fp16",
                        "params_b": nparams / 1e9, "load_s": load_s,
                        "weights_vram_gib": w_gib, "runs": rows,
                        "gpu_state_after": gpu_state()}
    del model
    vram_reset()


# ------------------------------------------------------------------ vision
VISION_MODEL = "openai/clip-vit-base-patch32"

def bench_vision():
    from transformers import CLIPVisionModel
    print(f"\n=== TIER 4: vision encode ({VISION_MODEL}) ===")
    vram_reset()
    t0 = time.perf_counter()
    model = CLIPVisionModel.from_pretrained(
        VISION_MODEL, dtype=torch.float16).to(DEV).eval()
    load_s = time.perf_counter() - t0
    print(f"  load: {load_s:.1f}s   VRAM(weights): {vram_peak_gib():.3f} GiB")

    rows = []
    for bs in [1, 8, 32, 128, 256]:
        vram_reset()
        # Deterministic synthetic 224x224 RGB batch, already normalized.
        g = torch.Generator(device="cpu").manual_seed(bs)
        px = torch.randn(bs, 3, 224, 224, generator=g).half().to(DEV)

        def run():
            with torch.inference_mode():
                model(pixel_values=px)

        med, best = timeit(run, warmup=3, iters=12)
        ips = bs / best
        print(f"  bs={bs:4d} 224x224  {best*1e3:8.2f} ms  {ips:9.1f} img/s  "
              f"VRAM {vram_peak_gib():.3f} GiB")
        rows.append({"batch": bs, "resolution": "224x224", "best_ms": best * 1e3,
                     "median_ms": med * 1e3, "images_per_s": ips,
                     "vram_gib": vram_peak_gib()})
        del px
        vram_reset()

    RESULTS["vision"] = {"model": VISION_MODEL, "dtype": "fp16",
                         "load_s": load_s, "runs": rows,
                         "gpu_state_after": gpu_state()}
    del model
    vram_reset()


if __name__ == "__main__":
    p = torch.cuda.get_device_properties(0)
    env = {"torch": torch.__version__, "cuda_runtime": torch.version.cuda,
           "driver": os.popen("nvidia-smi --query-gpu=driver_version "
                              "--format=csv,noheader").read().strip(),
           "gpu": p.name, "sm": f"sm_{p.major}{p.minor}",
           "vram_total_gib": p.total_memory / 2**30, "sms": p.multi_processor_count,
           "gpu_state_before": gpu_state()}
    print("ENV:", json.dumps(env, indent=2))
    RESULTS["env"] = env

    which = sys.argv[1:] or ["roofline", "embed", "coder", "vision"]
    fns = {"roofline": bench_roofline, "embed": bench_embed,
           "coder": bench_coder, "vision": bench_vision}
    for name in which:
        try:
            fns[name]()
        except Exception as e:
            print(f"  !! {name} FAILED: {type(e).__name__}: {e}")
            RESULTS[name] = {"error": f"{type(e).__name__}: {e}"}

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results.json")
    with open(out, "w") as f:
        json.dump(RESULTS, f, indent=2)
    print(f"\nwrote {out}")
