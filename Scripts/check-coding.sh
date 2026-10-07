#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Services/CodingStats.swift Tests/CodingChecks.swift -o "$check_dir/check-coding"
"$check_dir/check-coding"
