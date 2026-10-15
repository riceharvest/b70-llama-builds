# b70-llama-builds

Prebuilt [llama.cpp](https://github.com/ggml-org/llama.cpp) for the **Intel Arc Pro B70** (Linux x86-64), built on
GitHub-hosted runners. It saves you the ~1 hour SYCL ahead-of-time build and the oneAPI install.

| download | what |
|---|---|
| [`llama-b70-sycl-ubuntu24-x64.tar.gz`](https://github.com/riceharvest/b70-llama-builds/releases/latest/download/llama-b70-sycl-ubuntu24-x64.tar.gz) | SYCL, AOT for `bmg-g31-a0`, F16, oneDNN, oneAPI runtime bundled. Fastest backend on the B70 today. |
| [`llama-b70-vulkan-ubuntu24-x64.tar.gz`](https://github.com/riceharvest/b70-llama-builds/releases/latest/download/llama-b70-vulkan-ubuntu24-x64.tar.gz) | Vulkan, upstream master + B70 decode/prefill fixes (`vk-b70-stack`). |
| [`SHA256SUMS`](https://github.com/riceharvest/b70-llama-builds/releases/latest/download/SHA256SUMS) | checksums |

```bash
curl -LO https://github.com/riceharvest/b70-llama-builds/releases/latest/download/llama-b70-sycl-ubuntu24-x64.tar.gz
curl -LO https://github.com/riceharvest/b70-llama-builds/releases/latest/download/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
tar xf llama-b70-sycl-ubuntu24-x64.tar.gz && cd llama-b70-sycl-ubuntu24-x64
ONEAPI_DEVICE_SELECTOR=level_zero:0 ./llama-server -m /path/to/model.gguf -ngl 99 -fa on -c 8192
```

Requirements: glibc 2.39+ (Ubuntu 24.04+, Fedora 40+, Debian 13+). SYCL needs the Intel GPU driver
(compute-runtime + Level Zero loader); Vulkan needs Mesa ANV. [b70-doctor](https://github.com/riceharvest/b70-doctor)
checks both. To benchmark these builds and add your numbers to the shared table in one command:
`curl -fsSL https://raw.githubusercontent.com/riceharvest/b70-bench/main/b70-bench.sh | bash -s -- --prebuilt --tier quick`
([b70-bench](https://github.com/riceharvest/b70-bench)). Each tarball has a `README.md` and `BUILDINFO.txt` (exact source commit, toolchain, CI run).

## Docker image

`ghcr.io/riceharvest/b70-llama` has both builds plus its own GPU userspace from a pinned Arch Linux snapshot: Mesa ANV
26.2.x for Vulkan, compute-runtime and Level Zero for SYCL. The host only needs the `xe` kernel driver, so you get the
Mesa 26 Vulkan speed-up ([measured](https://github.com/riceharvest/awesome-b70/blob/main/performance.md#mesa-25-vs-26)) even on
an older distro.

```bash
mkdir -p ~/models && alias b70='docker run --rm -it --device /dev/dri -v ~/models:/models -p 8080:8080 ghcr.io/riceharvest/b70-llama'
# Qwen3.6-35B-A3B with its MTP head (Vulkan + MTP n=3: 108.5 tok/s with identical output on Mesa 25; the image has Mesa 26)
b70 get unsloth/Qwen3.6-35B-A3B-MTP-GGUF Qwen3.6-35B-A3B-UD-Q4_K_M.gguf Qwen3.6-35B-A3B-MTP-UD-Q4_K_M.gguf
b70 vulkan -m /models/Qwen3.6-35B-A3B-MTP-UD-Q4_K_M.gguf -fa on -c 32768 --spec-type draft-mtp --spec-draft-n-max 3
# Qwen3.8-27B (dense): Vulkan on Mesa 26 decodes 25.3 tok/s vs 21.9 on SYCL
b70 get unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-Q4_K_M.gguf
b70 vulkan -m /models/Qwen3.8-27B-UD-Q4_K_M.gguf -fa on -c 32768
```

`b70 sycl ...` serves with the SYCL build instead (faster on long prompts). `b70 bench vulkan -m /models/x.gguf` runs
llama-bench, `b70 info` lists versions and GPUs. The server listens on `0.0.0.0:8080` with all layers on the GPU unless
you pass your own `--host`, `--port`, `-ngl`. If more than one GPU is visible (an Intel iGPU next to the B70, say), it serves on
the Battlemage card and says which; `-dev` picks another. With podman or as non-root, add `--group-add keep-groups` (podman) or the
host's `render` group id. Built on GitHub-hosted runners by `.github/workflows/image.yml` after each release; CI checks
that every library resolves and the Vulkan build runs on lavapipe (no GPU there).

## What is pinned

[`refs.env`](refs.env) holds the source commits and toolchain versions. Pushing a change there rebuilds and publishes
a new release.

- SYCL: [riceharvest/llama.cpp `sycl-b70-release`](https://github.com/riceharvest/llama.cpp/tree/sycl-b70-release)
  `56cb978b7` = upstream `a0e6dc738` + B70 SYCL fixes: the qwen35moe decode fusions (on by default; set
  `GGML_SYCL_ENABLE_FUSION=0` to turn them all off), the fused MoE GEMV for 2-8 token batches (makes MTP faster than no
  MTP), a flash-attention KV split sized for Xe2, GQA padding in the tile FA kernel (`GGML_SYCL_FA_TILE_GQA_PAD=0` turns
  it off) and a oneDNN alignment fix. Measured on a B70: Qwen3.6-35B-A3B UD-Q4_K_M decode 93.4 -> 107.9 tok/s with the
  fusions; MTP n=3 80.9 -> 131.8 tok/s with the MoE GEMV; both together +39% over fusions alone (121.7 vs 87.5 tok/s in
  one session that ran ~8% below the others); at 32K context 64.1 -> 75.2 tok/s with the FA split. Qwen3.8-27B UD-Q4_K_XL
  at 32K: 14.6 -> 18.6 tok/s with the FA split + GQA padding. TODO(025): release-candidate check before merging.
  oneAPI 2025.3 from Intel's apt repo, ocloc from compute-runtime 26.27.
- Vulkan: [riceharvest/llama.cpp `vk-b70-stack`](https://github.com/riceharvest/llama.cpp/tree/vk-b70-stack)
  `54b6e8485`, Vulkan SDK 1.4.363.0. On a B70 with Mesa 25.3.6 it took Qwen3.8-27B decode from 13.2 to 22.7 tok/s
  and Qwen3.6-35B-A3B from 39 to 64 tok/s vs upstream master. These fixes are not upstream (yet).
  What each fix does and how to reproduce the numbers: [branch docs](https://github.com/riceharvest/llama.cpp/blob/b70-docs/README.md).

## What CI checks (no GPU on the runners)

- Every binary and library resolves with no oneAPI install (`ldd`, only the system Level Zero loader / Vulkan loader
  may be missing).
- Vulkan: `test-backend-ops -o MUL_MAT` on lavapipe (CPU Vulkan) for the quant types the stack's shaders change, and
  a tiny model generating text.
- SYCL: the binaries start (`--version`, `--help`). Kernel correctness on real hardware is tested on a B70 before a
  commit is pinned here, not in CI.

Part of [awesome-b70](https://github.com/riceharvest/awesome-b70). Not affiliated with Intel or ggml-org.
Licenses: llama.cpp is MIT; the bundled oneAPI runtime libraries are distributed under Intel's license terms (texts in
each tarball's `licenses/`). This repo's scripts: MIT.
