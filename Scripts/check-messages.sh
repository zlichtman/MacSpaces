#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Core/Messaging/*.swift Sources/Services/Messaging/MessagesScripts.swift Sources/Services/AppleScriptRunner.swift Tests/MessageChecks.swift -o "$check_dir/check-messages"
"$check_dir/check-messages"
