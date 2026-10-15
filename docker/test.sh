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
echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]
