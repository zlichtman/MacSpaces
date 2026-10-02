#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Services/Coding/CodingUsageReader.swift Tests/CodingUsageChecks.swift -o "$check_dir/check-usage"
"$check_dir/check-usage"
