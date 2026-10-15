#!/bin/bash
# Copy every oneAPI shared library the binaries in $1 need (ldd closure + the Level Zero UR adapters + MKL CPU
# dispatch libs) into $1, and set RUNPATH=$ORIGIN on them, so the tarball runs without a oneAPI install.
# The Level Zero loader (libze_loader.so.1) and the GPU driver are NOT bundled: they come with the system's
# compute-runtime install. Run after `source /opt/intel/oneapi/setvars.sh`.
set -euo pipefail
BIN=$1; ROOT=${ONEAPI_ROOT:-/opt/intel/oneapi}
declare -A seen
queue=()
for f in "$BIN"/*; do [ -f "$f" ] && [ ! -L "$f" ] && file -b "$f" | grep -q ELF && queue+=("$f"); done
# loaded with dlopen at runtime, so ldd can't see them
for pat in 'libur_adapter_level_zero*.so*' 'libmkl_def.so*' 'libmkl_avx2.so*' 'libmkl_avx512.so*' 'libmkl_vml_def.so*' 'libmkl_vml_avx2.so*' 'libmkl_vml_avx512.so*'; do
  while IFS= read -r f; do queue+=("$f"); done < <(find -L "$ROOT/compiler/$ONEAPI_VERSION/lib" "$ROOT/mkl/$ONEAPI_VERSION/lib" -maxdepth 1 -name "$pat" -type f 2>/dev/null)
done
copied=()
copy_one() { # copy the real file once; soname/dev names become relative symlinks to it
  local src=$1 name real rname; name=$(basename "$src")
  [ -n "${seen[$name]:-}" ] && return 0; seen[$name]=1
  real=$(readlink -f "$src"); rname=$(basename "$real")
  if [ "$rname" != "$name" ]; then copy_one "$real"; ln -sfn "$rname" "$BIN/$name"
  else cp "$real" "$BIN/$name"; copied+=("$BIN/$name"); fi
}
while [ ${#queue[@]} -gt 0 ]; do
  f=${queue[0]}; queue=("${queue[@]:1}")
  case "$f" in "$ROOT"/*) copy_one "$f";; esac
  while IFS= read -r dep; do
    [ -n "$dep" ] && [ -z "${seen[$(basename "$dep")]:-}" ] && queue+=("$dep")
  done < <(ldd "$f" 2>/dev/null | awk '$3 ~ "^/" {print $3}' | grep "^$ROOT/" || true)
done
for f in "${copied[@]}"; do chmod u+w "$f"; patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || echo "patchelf skipped: $f"; done
printf '%s\n' "${copied[@]##*/}" | sort > "$BIN/ONEAPI_BUNDLED.txt"
echo "bundled $(wc -l < "$BIN/ONEAPI_BUNDLED.txt") oneAPI libraries ($(du -shc "${copied[@]}" | tail -1 | cut -f1))"
