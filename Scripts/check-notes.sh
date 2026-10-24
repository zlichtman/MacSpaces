#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Core/Persistence/NoteRepository.swift Tests/NoteChecks.swift -o "$check_dir/check-notes"
"$check_dir/check-notes"
