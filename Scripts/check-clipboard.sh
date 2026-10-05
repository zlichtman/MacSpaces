#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Services/ClipboardHistory.swift Sources/Services/ClipboardCapture.swift Sources/Services/MaccyImport.swift Sources/Services/SecureStorage.swift Tests/ClipboardChecks.swift -o "$check_dir/check-clipboard"
"$check_dir/check-clipboard"
