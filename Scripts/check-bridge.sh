#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Core/Bridge/*.swift Tests/BridgeChecks.swift -o "$check_dir/check-bridge"
"$check_dir/check-bridge"
