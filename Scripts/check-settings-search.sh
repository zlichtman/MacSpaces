#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Settings/SettingsSearch.swift Tests/SettingsSearchChecks.swift -o "$check_dir/check-settings-search"
"$check_dir/check-settings-search"
