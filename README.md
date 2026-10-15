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

## What is pinned

[`refs.env`](refs.env) holds the source commits and toolchain versions. Pushing a change there rebuilds and publishes
a new release.

- SYCL: upstream llama.cpp `a0e6dc738` (measured on a B70: Qwen3.6-35B-A3B UD-Q4_K_M decode 97.7 tok/s,
  Qwen3.8-27B UD-Q4_K_XL 21.9 tok/s). oneAPI 2025.3 from Intel's apt repo, ocloc from compute-runtime 26.27.
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
