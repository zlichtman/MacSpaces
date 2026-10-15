#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks_dir=$(mktemp -d)
trap 'rm -rf "$checks_dir"' EXIT
swiftc -parse-as-library Sources/Services/AgentHookConfig.swift Tests/AgentHookChecks.swift -o "$checks_dir/agent-hook-checks"
"$checks_dir/agent-hook-checks"
