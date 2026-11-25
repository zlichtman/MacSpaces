#!/bin/bash
# The Status icon's readings: what a Mac has, each ring's fill, number and menu line, and when it warns.
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Core/Status/*.swift Tests/StatusChecks.swift -o "$check_dir/check-status"
"$check_dir/check-status"
