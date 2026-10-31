#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Modules/Notch/Core/NotchGeometry.swift Sources/Modules/Notch/UI/NotchShape.swift \
  Sources/Core/Agents/AgentPopoutLayout.swift Sources/Core/Agents/AgentFace.swift Tests/NotchChecks.swift -o "$check_dir/check-notch"
"$check_dir/check-notch"
