#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Services/ScriptAligner.swift Tests/PrompterChecks.swift -o "$check_dir/check-prompter"
"$check_dir/check-prompter"
