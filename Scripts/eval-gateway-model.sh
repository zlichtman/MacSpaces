#!/bin/bash
# Runs the gateway rules against Apple's real on-device model (Tests/GatewayModelEval.swift).
# Needs macOS 26 with Apple Intelligence on, so it isn't part of preflight or CI: run it on the Mac
# after changing GatewayJudge's prompts. Exits 0 when every case passes, 1 on a failure, 2 when the
# model isn't available.
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library -O Sources/Core/Wisp/*.swift Tests/GatewayModelEval.swift -o "$check_dir/eval-gateway-model" 2>&1 | grep -v "deprecated\|DeprecatedDeclaration\|^ *[0-9]* |\|^ *|\|^$" || true
"$check_dir/eval-gateway-model"
