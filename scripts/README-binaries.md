# llama.cpp for the Intel Arc Pro B70

Prebuilt by https://github.com/riceharvest/b70-llama-builds. See `BUILDINFO.txt` for the exact source commit and
toolchain. Linux x86-64, glibc 2.39 or newer (Ubuntu 24.04+, Fedora 40+, Debian 13+).

## SYCL tarball

- Kernels are compiled ahead of time for the B70 (`bmg-g31-a0`), so there is no multi-minute JIT on first start.
- The oneAPI runtime (SYCL, oneMKL, oneDNN, TBB, Unified Runtime) is bundled next to the binaries. You do **not**
  need to install or `source` oneAPI.
- You **do** need the Intel GPU driver stack: compute-runtime (`libze-intel-gpu1`/`intel-level-zero-gpu`) and the
  Level Zero loader (`libze1`/`level-zero`). Check with `b70-doctor` (https://github.com/riceharvest/b70-doctor).

```bash
ONEAPI_DEVICE_SELECTOR=level_zero:0 ./llama-server -m model.gguf -ngl 99 -fa on -c 8192
```

## Vulkan tarball

- Branch `vk-b70-stack` of https://github.com/riceharvest/llama.cpp: upstream master plus B70 fixes (32-bit MMVQ
  loads, Xe2 workgroup and split-k rules, 8x16x16 flash-attention shader, xe_fa decode split).
- Needs Mesa ANV and the Vulkan loader (`libvulkan1`). Mesa 26.1+ is much faster on Xe2 than 25.x.

```bash
GGML_VK_VISIBLE_DEVICES=0 ./llama-server -m model.gguf -ngl 99 -fa on -c 8192
```

## Check the install

`./test-backend-ops -o MUL_MAT -b SYCL0` (or `-b Vulkan0`) compares the GPU against the CPU backend.

Licenses: `licenses/` (llama.cpp MIT; Intel oneAPI runtime libraries under Intel's license terms, texts included).
