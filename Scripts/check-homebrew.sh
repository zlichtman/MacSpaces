#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Services/HomebrewCatalog.swift Tests/HomebrewChecks.swift -o "$check_dir/check-homebrew"
"$check_dir/check-homebrew"
