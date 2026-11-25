#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Core/Spaces/SpaceLayout.swift Tests/SpacesChecks.swift -o "$check_dir/check-spaces"
"$check_dir/check-spaces"
