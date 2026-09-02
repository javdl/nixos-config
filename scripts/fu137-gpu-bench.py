#!/usr/bin/env python3
"""fu137 GPU benchmark: roofline, embeddings, coding-model inference, vision.

Reproducible: pinned model revisions, fixed seeds, fixed corpora, warmup +
timed repeats, VRAM measured with torch.cuda.max_memory_allocated over a reset
baseline so the desktop's ~1.7 GiB is excluded.

Usage: python bench.py [roofline] [embed] [coder] [vision] [rerank] [vlm] [ollama]
         [--coder-model M] [--embed-model M] [--embed-seq N] [--vision-model M]
         [--vision-res N] [--rerank-model M] [--vlm-model M] [--ollama-model M]
         [--out results.json]
Default tiers: roofline embed coder vision.  Results are merged into --out,
keyed by tier and model, so repeated runs with different models accumulate.
"""
import argparse, gc, json, os, statistics, sys, time
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
EMBED_SEQ = 128

def bench_embed():
    from transformers import AutoTokenizer, AutoModel
    print(f"\n=== TIER 2: embeddings ({EMBED_MODEL}, seq {EMBED_SEQ}) ===")
    vram_reset()
    t0 = time.perf_counter()
    tok = AutoTokenizer.from_pretrained(EMBED_MODEL)
    model = AutoModel.from_pretrained(EMBED_MODEL, dtype=torch.float16,
                                      device_map=DEV).eval()
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
        enc = tok(batch, padding="max_length", truncation=True,
                  max_length=EMBED_SEQ, return_tensors="pt").to(DEV)
        ntok = int(enc["attention_mask"].numel())

        def run():
            with torch.inference_mode():
                o = model(**enc).last_hidden_state
                m = enc["attention_mask"].unsqueeze(-1)
                return (o * m).sum(1) / m.sum(1)

        med, best = timeit(run, warmup=3, iters=15)
        dps = bs / best
        tps = ntok / best
        print(f"  bs={bs:4d} seq={EMBED_SEQ}  {best*1e3:8.2f} ms  {dps:9.1f} docs/s  "
              f"{tps:11.0f} tok/s  VRAM {vram_peak_gib():.3f} GiB")
        rows.append({"batch": bs, "seq_len": EMBED_SEQ, "best_ms": best * 1e3,
                     "median_ms": med * 1e3, "docs_per_s": dps,
                     "tokens_per_s": tps, "vram_gib": vram_peak_gib()})

    RESULTS[f"embeddings:{EMBED_MODEL}"] = {"model": EMBED_MODEL, "dtype": "fp16",
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
        CODER_MODEL, dtype=torch.float16, device_map=DEV).eval()
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

    RESULTS[f"coder:{CODER_MODEL}"] = {"model": CODER_MODEL, "dtype": "fp16",
                        "params_b": nparams / 1e9, "load_s": load_s,
                        "weights_vram_gib": w_gib, "runs": rows,
                        "gpu_state_after": gpu_state()}
    del model
    vram_reset()


# ------------------------------------------------------------------ vision
VISION_MODEL = "openai/clip-vit-base-patch32"
VISION_RES = 224

def load_vision_tower(name):
    """Image tower only, for CLIP- and SigLIP-family checkpoints."""
    from transformers import AutoModel
    full = AutoModel.from_pretrained(name, dtype=torch.float16, device_map=DEV)
    return getattr(full, "vision_model", full).eval()

def bench_vision():
    print(f"\n=== TIER 4: vision encode ({VISION_MODEL}, {VISION_RES}px) ===")
    vram_reset()
    t0 = time.perf_counter()
    model = load_vision_tower(VISION_MODEL)
    load_s = time.perf_counter() - t0
    print(f"  load: {load_s:.1f}s   VRAM(weights): {vram_peak_gib():.3f} GiB")

    rows = []
    for bs in [1, 8, 32, 128, 256]:
        vram_reset()
        # Deterministic synthetic 224x224 RGB batch, already normalized.
        g = torch.Generator(device="cpu").manual_seed(bs)
        px = torch.randn(bs, 3, VISION_RES, VISION_RES, generator=g).half().to(DEV)

        def run():
            with torch.inference_mode():
                model(pixel_values=px)

        med, best = timeit(run, warmup=3, iters=12)
        ips = bs / best
        print(f"  bs={bs:4d} {VISION_RES}x{VISION_RES}  {best*1e3:8.2f} ms  {ips:9.1f} img/s  "
              f"VRAM {vram_peak_gib():.3f} GiB")
        rows.append({"batch": bs, "resolution": f"{VISION_RES}x{VISION_RES}",
                     "best_ms": best * 1e3,
                     "median_ms": med * 1e3, "images_per_s": ips,
                     "vram_gib": vram_peak_gib()})
        del px
        vram_reset()

    RESULTS[f"vision:{VISION_MODEL}"] = {"model": VISION_MODEL, "dtype": "fp16",
                         "load_s": load_s, "runs": rows,
                         "gpu_state_after": gpu_state()}
    del model
    vram_reset()


# ---------------------------------------------------------------- reranker
RERANK_MODEL = "BAAI/bge-reranker-v2-m3"

def bench_rerank():
    from transformers import AutoTokenizer, AutoModelForSequenceClassification
    print(f"\n=== TIER 2b: rerank ({RERANK_MODEL}) ===")
    vram_reset()
    t0 = time.perf_counter()
    tok = AutoTokenizer.from_pretrained(RERANK_MODEL)
    model = AutoModelForSequenceClassification.from_pretrained(
        RERANK_MODEL, dtype=torch.float16, device_map=DEV).eval()
    load_s = time.perf_counter() - t0
    print(f"  load: {load_s:.1f}s   VRAM(weights): {vram_peak_gib():.3f} GiB")

    query = "how does the ingestion pipeline retry failed batches"
    base = ("The ingestion service processes records in batches; on failure it applies "
            "exponential backoff and retries up to five times before dead-lettering. ")
    docs = [(base * 4)[: 300 + (i * 53) % 500] for i in range(512)]
    rows = []
    for bs in [1, 8, 32, 128]:
        vram_reset()
        pairs = [[query, d] for d in docs[:bs]]
        enc = tok(pairs, padding="max_length", truncation=True, max_length=512,
                  return_tensors="pt").to(DEV)

        def run():
            with torch.inference_mode():
                return model(**enc).logits.view(-1)

        med, best = timeit(run, warmup=3, iters=10)
        pps = bs / best
        print(f"  bs={bs:4d} seq=512  {best*1e3:8.2f} ms  {pps:8.1f} pairs/s  "
              f"VRAM {vram_peak_gib():.3f} GiB")
        rows.append({"batch": bs, "seq_len": 512, "best_ms": best * 1e3,
                     "median_ms": med * 1e3, "pairs_per_s": pps,
                     "vram_gib": vram_peak_gib()})
    RESULTS[f"rerank:{RERANK_MODEL}"] = {"model": RERANK_MODEL, "dtype": "fp16",
                                         "load_s": load_s, "runs": rows,
                                         "gpu_state_after": gpu_state()}
    del model
    vram_reset()


# --------------------------------------------------------------------- VLM
VLM_MODEL = "Qwen/Qwen2.5-VL-7B-Instruct"

def bench_vlm():
    """Image -> text: fixed 512x512 synthetic image, fixed prompt, 64 new tokens."""
    from PIL import Image
    import numpy as np
    from transformers import AutoProcessor, AutoModelForImageTextToText
    print(f"\n=== TIER 4b: vision-language ({VLM_MODEL}) ===")
    vram_reset()
    t0 = time.perf_counter()
    proc = AutoProcessor.from_pretrained(VLM_MODEL)
    model = AutoModelForImageTextToText.from_pretrained(
        VLM_MODEL, dtype=torch.float16, device_map=DEV).eval()
    load_s = time.perf_counter() - t0
    w_gib = vram_peak_gib()
    nparams = sum(p.numel() for p in model.parameters())
    print(f"  load: {load_s:.1f}s   params: {nparams/1e9:.3f}B   "
          f"VRAM(weights): {w_gib:.3f} GiB")

    rng = np.random.default_rng(0)
    img = Image.fromarray(rng.integers(0, 255, (512, 512, 3), dtype=np.uint8))
    msgs = [{"role": "user", "content": [
        {"type": "image"},
        {"type": "text", "text": "Describe the garment in this product photo: "
                                 "category, colour, material, and style."}]}]
    text = proc.apply_chat_template(msgs, add_generation_prompt=True)
    NEW = 64
    rows = []
    for bs in [1, 4]:
        vram_reset()
        enc = proc(text=[text] * bs, images=[img] * bs, padding=True,
                   return_tensors="pt").to(DEV)
        in_tok = int(enc["input_ids"].shape[1])

        def run():
            with torch.inference_mode():
                model.generate(**enc, max_new_tokens=NEW, min_new_tokens=NEW,
                               do_sample=False)

        med, best = timeit(run, warmup=1, iters=3)
        ipm = bs / best * 60
        print(f"  bs={bs:2d} 512px in_tok={in_tok}  {best*1e3:8.0f} ms  "
              f"{ipm:7.1f} img/min  {bs*NEW/best:6.1f} tok/s  VRAM {vram_peak_gib():.3f} GiB")
        rows.append({"batch": bs, "image_px": 512, "input_tokens": in_tok,
                     "new_tokens": NEW, "best_ms": best * 1e3, "median_ms": med * 1e3,
                     "images_per_min": ipm, "tok_per_s": bs * NEW / best,
                     "vram_gib": vram_peak_gib()})
    RESULTS[f"vlm:{VLM_MODEL}"] = {"model": VLM_MODEL, "dtype": "fp16",
                                   "params_b": nparams / 1e9, "load_s": load_s,
                                   "weights_vram_gib": w_gib, "runs": rows,
                                   "gpu_state_after": gpu_state()}
    del model
    vram_reset()


# ------------------------------------------------------------------ ollama
OLLAMA_MODEL = "qwen3-coder:30b"
OLLAMA_URL = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")

def bench_ollama():
    """GGUF via the ollama HTTP API. Throughput from ollama's own nanosecond
    counters (prompt_eval_*, eval_*), VRAM from nvidia-smi delta."""
    import subprocess, urllib.request
    print(f"\n=== TIER 3b: ollama ({OLLAMA_MODEL}) ===")

    def post(path, body):
        req = urllib.request.Request(f"{OLLAMA_URL}{path}", method="POST",
                                     data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=1800) as r:
            return json.loads(r.read())

    def smi_used_mib():
        return int(subprocess.run(["nvidia-smi", "--query-gpu=memory.used",
                                   "--format=csv,noheader,nounits"],
                                  capture_output=True, text=True).stdout.strip())

    base_mib = smi_used_mib()
    t0 = time.perf_counter()
    post("/api/generate", {"model": OLLAMA_MODEL, "prompt": "hi", "stream": False,
                           "keep_alive": "10m", "options": {"num_predict": 1}})
    load_s = time.perf_counter() - t0
    weights_mib = smi_used_mib() - base_mib
    print(f"  load: {load_s:.1f}s   VRAM(delta): {weights_mib/1024:.3f} GiB")

    filler = ("# utility helpers for the data ingestion service\n"
              "def normalize(record):\n    return {k: v for k, v in record.items() if v}\n\n")
    rows = []
    for ctx in [512, 2048, 8192]:
        prompt = (filler * (ctx // 20 + 40))[: int(ctx * 4.1)]  # ~ctx tokens (measured 3.0 chars/tok on this filler)
        NEW = 128
        best = None
        for i in range(3):
            # Unique first line per request defeats ollama's prefix KV cache,
            # so prompt_eval_duration measures a real prefill every time.
            nonce = f"# run {ctx}-{i}-{time.time_ns()}\n"
            r = post("/api/generate", {
                "model": OLLAMA_MODEL, "prompt": nonce + prompt, "stream": False,
                "keep_alive": "10m",
                "options": {"num_predict": NEW, "num_ctx": 16384, "temperature": 0,
                            "seed": 0}})
            if best is None or r["eval_duration"] < best["eval_duration"]:
                best = r
        pe_tps = best["prompt_eval_count"] / (best["prompt_eval_duration"] / 1e9)
        de_tps = best["eval_count"] / (best["eval_duration"] / 1e9)
        peak_mib = smi_used_mib() - base_mib
        print(f"  ctx={best['prompt_eval_count']:5d}  prefill {pe_tps:8.0f} tok/s  |  "
              f"decode {de_tps:6.1f} tok/s ({best['eval_count']} new)  "
              f"VRAM {peak_mib/1024:.3f} GiB")
        rows.append({"ctx": best["prompt_eval_count"],
                     "prefill_tok_per_s": pe_tps, "new_tokens": best["eval_count"],
                     "decode_tok_per_s": de_tps, "vram_gib": peak_mib / 1024})
    RESULTS[f"ollama:{OLLAMA_MODEL}"] = {"model": OLLAMA_MODEL, "load_s": load_s,
                                         "weights_vram_gib": weights_mib / 1024,
                                         "runs": rows, "gpu_state_after": gpu_state()}
    post("/api/generate", {"model": OLLAMA_MODEL, "keep_alive": 0})


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("tiers", nargs="*", default=["roofline", "embed", "coder", "vision"])
    ap.add_argument("--coder-model", default=CODER_MODEL)
    ap.add_argument("--embed-model", default=EMBED_MODEL)
    ap.add_argument("--embed-seq", type=int, default=EMBED_SEQ)
    ap.add_argument("--vision-model", default=VISION_MODEL)
    ap.add_argument("--vision-res", type=int, default=VISION_RES)
    ap.add_argument("--rerank-model", default=RERANK_MODEL)
    ap.add_argument("--vlm-model", default=VLM_MODEL)
    ap.add_argument("--ollama-model", default=OLLAMA_MODEL)
    ap.add_argument("--out", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "results.json"))
    a = ap.parse_args()
    CODER_MODEL, EMBED_MODEL, EMBED_SEQ = a.coder_model, a.embed_model, a.embed_seq
    VISION_MODEL, VISION_RES = a.vision_model, a.vision_res
    RERANK_MODEL, VLM_MODEL, OLLAMA_MODEL = a.rerank_model, a.vlm_model, a.ollama_model
    if os.path.exists(a.out):
        with open(a.out) as f:
            RESULTS.update(json.load(f))

    p = torch.cuda.get_device_properties(0)
    env = {"torch": torch.__version__, "cuda_runtime": torch.version.cuda,
           "driver": os.popen("nvidia-smi --query-gpu=driver_version "
                              "--format=csv,noheader").read().strip(),
           "gpu": p.name, "sm": f"sm_{p.major}{p.minor}",
           "vram_total_gib": p.total_memory / 2**30, "sms": p.multi_processor_count,
           "gpu_state_before": gpu_state()}
    print("ENV:", json.dumps(env, indent=2))
    RESULTS["env"] = env

    fns = {"roofline": bench_roofline, "embed": bench_embed,
           "coder": bench_coder, "vision": bench_vision, "rerank": bench_rerank,
           "vlm": bench_vlm, "ollama": bench_ollama}
    for name in a.tiers:
        try:
            fns[name]()
        except Exception as e:
            print(f"  !! {name} FAILED: {type(e).__name__}: {e}")
            RESULTS[f"{name}:error"] = {"error": f"{type(e).__name__}: {e}"}
        with open(a.out, "w") as f:
            json.dump(RESULTS, f, indent=2)
    print(f"\nwrote {a.out}")
