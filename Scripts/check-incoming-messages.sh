#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Services/Messaging/IncomingMessagesReader.swift Tests/IncomingMessagesChecks.swift -o "$check_dir/check-incoming"
"$check_dir/check-incoming"
