#!/bin/bash
# Every file in Sources/Debug is a check harness that only Debug builds compile. One without
# `#if DEBUG` breaks the Release build, which preflight and CI don't build, only ship.sh does.
set -euo pipefail
cd "$(dirname "$0")/.."
missing=()
for file in Sources/Debug/*.swift; do
  grep -q '^#if DEBUG' "$file" || missing+=("$file")
done
if [ ${#missing[@]} -gt 0 ]; then
  printf 'check-debug-guards: wrap in #if DEBUG: %s\n' "${missing[@]}" >&2
  exit 1
fi
echo "check-debug-guards: every Sources/Debug file is Debug-only"
