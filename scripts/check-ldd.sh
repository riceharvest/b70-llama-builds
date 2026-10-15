#!/bin/bash
# Fail if any ELF file in $1 has an unresolved library, ignoring the ones the system must provide ($2, regex).
set -uo pipefail
BIN=$1; ALLOW=${2:-'^$'}; bad=0
for f in "$BIN"/*; do
  [ -f "$f" ] && file -b "$f" | grep -q ELF || continue
  miss=$(env -u LD_LIBRARY_PATH ldd "$f" 2>/dev/null | awk '/not found/ {print $1}' | grep -Ev "$ALLOW" | sort -u | tr '\n' ' ' || true)
  [ -n "$miss" ] && { echo "UNRESOLVED in $(basename "$f"): $miss"; bad=1; }
done
[ $bad = 0 ] && echo "ldd: all libraries resolve (allowed missing: $ALLOW)"
exit $bad
