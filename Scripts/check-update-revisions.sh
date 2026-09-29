#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc Sources/Services/ReleaseRevision.swift Tests/UpdateRevisionChecks.swift -o "$check_dir/check-updates"
"$check_dir/check-updates"
