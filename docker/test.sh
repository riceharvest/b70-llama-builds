#!/usr/bin/env bash
# CPU-only tests of the b70-llama entry script against fake llama binaries (run in CI and locally).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
check() { if printf '%s\n' "$2" | grep -qE -- "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$1]: /$3/ not in:"; printf '%s\n' "$2" | sed 's/^/    | /'; fi; }
refute() { if printf '%s\n' "$2" | grep -qE -- "$3"; then FAIL=$((FAIL+1)); echo "FAIL [$1]: unexpected /$3/"; printf '%s\n' "$2" | sed 's/^/    | /'; else PASS=$((PASS+1)); fi; }
for be in sycl vulkan; do
  mkdir -p "$TMP/llama/$be"
  for bin in llama-server llama-bench; do
    cat > "$TMP/llama/$be/$bin" <<'F'
#!/usr/bin/env bash
if [ "${1:-}" = --list-devices ]; then
  echo "Available devices:"
  printf '%s\n' "${FAKE_DEVICES:-  X0: Intel(R) Arc(TM) Pro B70 Graphics (31000 MiB, 30000 MiB free)}"
  exit 0
fi
echo "ARGS: $*"
F
    chmod +x "$TMP/llama/$be/$bin"
  done
done
run() { B70_LLAMA_DIR="$TMP/llama" B70_SKIP_DRI_CHECK=1 bash "$HERE/b70-llama" "$@" 2>&1; }
# fake curl: writes the -o file, no network
mkdir -p "$TMP/fakebin"; printf '%s\n' '#!/usr/bin/env bash' 'for x in "$@"; do case "$x" in *api/models/*) printf "%s" "$FAKE_API_JSON"; exit 0 ;; esac; done' 'while [ $# -gt 0 ]; do [ "$1" = -o ] && echo fake > "$2"; shift; done' > "$TMP/fakebin/curl"; chmod +x "$TMP/fakebin/curl"
o=$(run vulkan -m /models/x.gguf); check one "$o" '^ARGS: --host 0.0.0.0 --port 8080 -ngl 99 -m /models/x.gguf$'; refute one "$o" 'GPUs visible'
export FAKE_DEVICES='  SYCL0: Intel(R) Arc(TM) Graphics (47000 MiB, 46000 MiB free)
  SYCL1: Intel(R) Arc(TM) Pro B70 Graphics (31000 MiB, 30000 MiB free)'
o=$(run sycl -m /models/x.gguf); check igpu "$o" '2 GPUs visible, using SYCL1 \(Intel\(R\) Arc\(TM\) Pro B70 Graphics\)'; check igpu "$o" '^ARGS: .* -dev SYCL1 -m /models/x.gguf$'
o=$(run sycl -m /models/x.gguf -dev SYCL0); check own "$o" '^ARGS: .*-dev SYCL0$'; refute own "$o" 'GPUs visible'
o=$(run bench sycl -m /models/x.gguf); check bench "$o" '^ARGS: -dev SYCL1 -m /models/x.gguf$'
export FAKE_DEVICES='  Vulkan0: Intel(R) Graphics (BMG G31) (31000 MiB, 30000 MiB free)
  Vulkan1: AMD Radeon RX 7600 (8000 MiB, 7000 MiB free)'
o=$(run vulkan -m /models/x.gguf); check bmg "$o" 'using Vulkan0'
o=$(run get 'a/../b' x.gguf); check get "$o" 'unexpected repo or file name'
# bolt: files already in the models dir -> no download; flags; --no-draft / --no-vision; BOLT_MODEL; download of a missing file
unset FAKE_DEVICES
mkdir -p "$TMP/models/bolt"
for f in NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB.gguf mmproj-NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB.gguf NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB-LiLiCorr.gguf; do echo x > "$TMP/models/bolt/$f"; done
runm() { B70_MODELS_DIR="$TMP/models" run "$@"; }
o=$(runm bolt); check bolt "$o" "^ARGS: --host 0.0.0.0 --port 8080 -ngl 99 -fa on -c 32768 -np 1 --jinja --temp 1.0 --top-p 0.95 -m $TMP/models/bolt/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB.gguf --mmproj .*mmproj-NVIDIA.* --no-mmproj-offload --spec-type draft-dflash --spec-draft-model .*LiLiCorr.gguf --spec-draft-ngl 99 --spec-draft-n-max 6$"
refute bolt "$o" 'downloading'
o=$(runm bolt --no-draft --no-vision -c 8192); check bolt-off "$o" '^ARGS: .* -m [^ ]*24GB.gguf -c 8192$'; refute bolt-off "$o" 'spec-type|mmproj'
o=$(B70_MODELS_DIR="$TMP/models" BOLT_MODEL=/models/own-Q4_K_M.gguf run bolt --no-draft); check bolt-own "$o" '-m /models/own-Q4_K_M.gguf --mmproj'
rm "$TMP/models/bolt/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB-LiLiCorr.gguf"
o=$(B70_MODELS_DIR="$TMP/models" PATH="$TMP/fakebin:$PATH" run bolt); check bolt-fetch "$o" 'downloading nvidia/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB-LiLiCorr-GGUF/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB-LiLiCorr.gguf'
check bolt-fetch "$o" '^ARGS: .*--spec-draft-model'
# bolt --quant: our repo (single file at the root, or split parts in a folder), no -ngl (llama.cpp --fit decides)
export FAKE_API_JSON='{"siblings":[{"rfilename":"README.md"},{"rfilename":"NVIDIA-Nemotron-3.5-Bolt-74B-A9B-IQ4_XS.gguf"},{"rfilename":"Q8_0/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-Q8_0-00002-of-00002.gguf"},{"rfilename":"Q8_0/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-Q8_0-00001-of-00002.gguf"},{"rfilename":"mmproj-NVIDIA-Nemotron-3.5-Bolt-74B-A9B-Q8_0.gguf"}]}'
rq() { B70_MODELS_DIR="$TMP/models" PATH="$TMP/fakebin:$PATH" run bolt "$@"; }
o=$(rq --quant IQ4_XS --no-draft); check quant "$o" "downloading darioooooo0o/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-GGUF/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-IQ4_XS.gguf"
check quant "$o" "^ARGS: --host 0.0.0.0 --port 8080 -fa on -c 32768 .* -m $TMP/models/bolt/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-IQ4_XS.gguf --mmproj"
refute quant "$o" ' -ngl 99'
check quant "$o" "--mmproj $TMP/models/bolt/mmproj-NVIDIA-Nemotron-3.5-Bolt-74B-A9B-Q8_0.gguf"
o=$(rq --quant Q8_0 --no-draft --no-vision); check quant-split "$o" 'downloading .*/Q8_0/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-Q8_0-00002-of-00002.gguf'
check quant-split "$o" "^ARGS: .* -m $TMP/models/bolt/Q8_0/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-Q8_0-00001-of-00002.gguf$"
[ -s "$TMP/models/bolt/Q8_0/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-Q8_0-00002-of-00002.gguf" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [quant-split]: part 2 not downloaded"; }
o=$(rq --quant Q5_K_M); check quant-missing "$o" 'no Q5_K_M file in darioooooo0o'
o=$(rq --quant 'Q4/../x'); check quant-bad "$o" 'bad --quant'
echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
