#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Modules/Notch/Core/NotchWindow.swift Sources/Modules/Notch/Core/HiddenApps.swift Tests/WindowChecks.swift -o "$check_dir/check-window"
"$check_dir/check-window"
