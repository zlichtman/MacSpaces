#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Core/Time/*.swift Tests/ClockChecks.swift -o "$check_dir/check-clock"
"$check_dir/check-clock"
