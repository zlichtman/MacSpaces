#!/bin/bash
# Studio without audio: what Read reads, takes (star, keep the best), styles, pace and names.
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Core/Studio/*.swift Tests/StudioChecks.swift -o "$check_dir/check-studio"
"$check_dir/check-studio"
