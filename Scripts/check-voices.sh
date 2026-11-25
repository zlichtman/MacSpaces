#!/bin/bash
# Voices from recordings, without models: sorting people across recordings, the speaking engine
# and the model store (Sources/Core/Voices).
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Core/Voices/*.swift Tests/VoiceChecks.swift -o "$check_dir/check-voices"
"$check_dir/check-voices"
