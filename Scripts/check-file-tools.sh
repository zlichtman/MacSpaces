#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Services/LocalFileTools.swift Sources/Modules/Converter/FileConverter.swift Sources/Core/Files/CompletedFileTracker.swift Tests/FileToolChecks.swift -o "$check_dir/check-file-tools"
"$check_dir/check-file-tools"
