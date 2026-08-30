# fu137 local inference: GPU inventory, benchmark, and setup

fu137 is a Mac-less Arch/Omarchy workstation with an RTX 3090. This document
records what the GPU stack actually contains, what it measures at, and what to
install if the box becomes a persistent local-inference host.

Nothing in section A or B has been applied. Review before running any of it.

Harness: [`scripts/fu137-gpu-bench.py`](../scripts/fu137-gpu-bench.py)
Raw numbers: [`docs/fu137-gpu-bench-results.json`](fu137-gpu-bench-results.json)
(covers tiers 2-4; the tier 1 roofline run's output file was overwritten before
the merge, so those figures live only in the table below. Re-run
`fu137-gpu-bench.py roofline` to regenerate them.)

## Inventory (2026-08-29)

| Layer | State |
|---|---|
| GPU | RTX 3090, 24 GiB, sm_86, 82 SMs, driver 610.57.04 (CUDA UMD 13.3) |
| CPU / RAM | Ryzen 9 7950X 16C/32T, 30 GiB RAM (12 GiB available, 16 GiB of 60 GiB swap in use) |
| Disk | 930 G root, 784 G free. `/tmp` is a **16 GiB tmpfs** |
| CUDA toolkit | Absent. No `nvcc`, no cuDNN/NCCL/TensorRT; only the driver's `libcuda.so` |
| Containers | `docker` binary present, daemon inactive, `joost` not in `docker` group, no `nvidia-container-toolkit` |
| Local models | None. No ollama/llama.cpp/vLLM; no `~/.ollama`, no HF cache |
| Plumbing | Determinate Nix 3.22.2, uv 0.11.21, mise |

## Benchmark results

Run with an ephemeral `uv` venv; PyTorch 2.13.0+cu130 wheels bundle their own CUDA
runtime, so this needed **no system-level installs**: no toolkit, no root, no docker group.

    uv venv --python 3.12 .venv
    uv pip install torch numpy transformers accelerate pillow
    ./.venv/bin/python scripts/fu137-gpu-bench.py            # all tiers
    ./.venv/bin/python scripts/fu137-gpu-bench.py roofline   # or one tier

Set `HF_HOME=~/.cache/huggingface` (the default). Do **not** put the model cache under
`/tmp`; see the tmpfs note in A4.

### Tier 1: roofline (N=8192 GEMM, best of 20 after warmup)

| | TFLOP/s | vs. 3090 spec |
|---|---|---|
| fp32 (tf32 off) | 25.09 | |
| fp32 (tf32 on) | 38.38 | |
| fp16 tensor-core | **71.38** | ~100% of 71 |
| bf16 tensor-core | 72.60 | ~100% |
| device copy (4 GiB) | **846 GB/s** | 90% of 936 |

The GPU performs at spec and does not throttle: 307 W, 47 C, 1995 MHz under load.

### Tier 2: embeddings (bge-small-en-v1.5, fp16, seq 128)

| batch | latency | docs/s | tok/s | VRAM |
|---|---|---|---|---|
| 1 | 2.26 ms | 443 | 56.7 K | 0.072 GiB |
| 8 | 2.29 ms | 3 500 | 448 K | 0.080 GiB |
| 32 | 5.46 ms | 5 857 | 750 K | 0.104 GiB |
| 128 | 18.54 ms | 6 904 | 884 K | 0.203 GiB |
| 256 | 34.67 ms | **7 383** | **945 K** | 0.334 GiB |

### Tier 3: coding-model inference (Qwen2.5-Coder-1.5B-Instruct, fp16, 1.544 B params, 2.876 GiB weights)

| ctx | prefill | prefill tok/s | decode tok/s | VRAM |
|---|---|---|---|---|
| 512 | 33.6 ms | 15 223 | 114.1 | 3.04 GiB |
| 2048 | 119.9 ms | 17 082 | 118.5 | 3.53 GiB |
| 8192 | 529.6 ms | 15 469 | **121.4** | 5.45 GiB |

### Tier 4: vision encode (CLIP ViT-B/32 image tower, fp16, 224x224)

| batch | latency | img/s | VRAM |
|---|---|---|---|
| 1 | 1.57 ms | 635 | 0.183 GiB |
| 8 | 2.72 ms | 2 936 | 0.190 GiB |
| 32 | 7.65 ms | 4 181 | 0.224 GiB |
| 128 | 25.40 ms | 5 039 | 0.361 GiB |
| 256 | 49.94 ms | **5 126** | 0.546 GiB |

## What the numbers say

**Decode leaves 56% on the table.** 2.876 GiB of weights are read per decoded token.
Against the measured 846 GB/s that puts the ceiling at **274 tok/s**, and HF
`generate()` delivers 121. The gap is Python and eager-mode overhead, not hardware.
The next benchmark worth running is the same model under `ollama-cuda` or llama.cpp,
compared against that 274 tok/s roofline. With 22.4 GiB of VRAM free you can also step
up to a 7B fp16 or a 32B Q4 coder in the same harness.

**RAM is the constraint, VRAM is not.** No tier exceeded 5.5 GiB of VRAM. Meanwhile the
box has 12 GiB of RAM available with 16 GiB already swapped, and `/tmp` is RAM-backed.

---

## Constraint that drives every choice below

fu137 currently boots **Arch/Omarchy**, not NixOS. Its entire Nix surface is:

    # flake.nix:187
    omarchyHome = mkOmarchyHome {
      hostName = "fu137";
      extraPackages = pkgs: [ pkgs.playerctl ];
    };

That is a **standalone Home Manager** profile — no system services, no kernel modules,
no /etc. There is also **no nixGL** anywhere in this repo, so a Nix-built CUDA binary
(`pkgs.ollama-cuda`) has no supported way to find Arch's `/usr/lib/libcuda.so.1`.

=> GPU runtimes on fu137 must come from **pacman**, not Nix. The Nix layer stays for
non-GPU CLI helpers only. Everything below is split accordingly.

---

## A. Arch/Omarchy (the OS fu137 actually runs) — pacman + systemd

### A1. GPU containers (needed for `docker run --gpus`)

Currently: docker daemon inactive, `joost` NOT in the `docker` group, no
`nvidia-container-toolkit`, no `nvidia` runtime in `/etc/docker/daemon.json`.

    sudo pacman -S --needed nvidia-container-toolkit     # extra/1.20.0-1, 44 MiB
    sudo nvidia-ctk runtime configure --runtime=docker   # !! REWRITES /etc/docker/daemon.json
    sudo usermod -aG docker joost                        # log out/in to take effect
    sudo systemctl enable --now docker

**Back up `/etc/docker/daemon.json` first.** It already carries non-default settings
(custom `bip = 172.17.0.1/16`, `dns`, log rotation); `nvidia-ctk` merges into it but
verify those three keys survive:

    sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
    # after: diff <(jq -S . /etc/docker/daemon.json.bak) <(jq -S . /etc/docker/daemon.json)

Verify: `docker run --rm --gpus all nvidia/cuda:13.0.0-base-ubuntu24.04 nvidia-smi`

Adding joost to `docker` grants root-equivalent access to the host. Rootless docker or
podman avoids that if it matters here.

### A2. A persistent local model server

    sudo pacman -S --needed ollama-cuda                  # extra/0.32.15-1, 988 MiB
    sudo systemctl enable --now ollama

Prefer `ollama-cuda` over `ollama` (CPU-only). It ships its own CUDA runtime, so the
4.71 GiB `cuda` toolkit package is NOT required.

Point models at the big disk, since / has 784 GiB free and /tmp is a 16 GiB tmpfs:

    # /etc/systemd/system/ollama.service.d/override.conf
    [Service]
    Environment="OLLAMA_MODELS=/var/lib/ollama/models"
    Environment="OLLAMA_KEEP_ALIVE=30m"
    Environment="OLLAMA_FLASH_ATTENTION=1"

### A3. Do NOT install by default

- `cuda` (4.71 GiB) — only needed to *compile* kernels (custom ops, llama.cpp from
  source, bitsandbytes). Prebuilt wheels and `ollama-cuda` do not need it. This
  benchmark ran fine with no toolkit at all.
- `cudnn` (806 MiB) — pulled in only by frameworks that ask for the system copy;
  PyTorch wheels bundle their own.

### A4. Raise the /tmp tmpfs cap (optional, fixes the failure hit during this run)

/tmp is a 16 GiB tmpfs and was 71% full; a 3.1 GiB model download died with
`Disk quota exceeded (os error 122)`. tmpfs is RAM-backed and this box has only
30 GiB RAM with 16 GiB already swapped, so **raising this trades away RAM**:

    # /etc/systemd/system/tmp.mount.d/size.conf
    [Mount]
    Options=mode=1777,strictatime,nosuid,nodev,size=24G

Better alternative: leave /tmp alone and keep model caches on disk via
`HF_HOME=~/.cache/huggingface` (the default) — which is what this benchmark ended up doing.

---

## B. Nix layer (flake.nix) — non-GPU helpers only

```diff
       omarchyHome = mkOmarchyHome {
         hostName = "fu137";
-        extraPackages = pkgs: [ pkgs.playerctl ];
+        extraPackages = pkgs: [
+          pkgs.playerctl
+          # Local-inference helpers. Deliberately CPU-only / no CUDA linkage:
+          # Nix-built CUDA binaries cannot reach Arch's driver libs without nixGL,
+          # so the GPU runtimes (ollama-cuda, nvidia-container-toolkit) come from
+          # pacman instead. See docs/fu137-local-inference.md.
+          pkgs.aichat        # CLI client, talks to the ollama HTTP endpoint
+          pkgs.gollama       # manage/inspect local ollama models
+        ];
       };
```

Both verified present in this repo's pinned nixpkgs: `aichat-0.30.0`, `gollama-2.0.4`.
(`gguf-tools` and `huggingface-cli` are NOT in nixpkgs — do not reach for them.)

Apply with: `home-manager switch --flake ".#fu137"`

Do NOT add `pkgs.ollama-cuda` here. It will build/download ~1 GiB and then fail to
find the driver at runtime.

---

## C. NixOS side (`hosts/fu137.nix`) — only if fu137 is ever booted into NixOS

**This config is stale and does not describe the running machine.** Flagging rather
than fixing, since it is out of scope for the benchmark:

| `hosts/fu137.nix` says | Reality (`nvidia-smi`) |
|---|---|
| `networking.hostName = "fu137-4090-ML"` | actual hostname is `fu137` |
| runner name `fu137-AMD-RTX4090-runner` | GPU is an **RTX 3090**, not a 4090 |
| `modules/nvidia-drivers-535.nix`, pinned 535.154.05, comment references a 4070 SUPER | Arch side runs **610.57.04** |

If you do bring NixOS up on this box, the GPU-container equivalent of A1 is:

```diff
   boot.kernel.sysctl."net.ipv4.ip_forward" = true; # Docker
   virtualisation.docker.enable = true;
+  hardware.nvidia-container-toolkit.enable = true;   # gives docker --gpus
+  users.users.joost.extraGroups = [ "networkmanager" "wheel" "docker" ];
+
+  services.ollama = {
+    enable = true;
+    acceleration = "cuda";
+    models = "/var/lib/ollama/models";
+  };
```

`hardware.nvidia-container-toolkit.enable` requires `hardware.graphics.enable`, which
`modules/nvidia-drivers-535.nix` already sets.
