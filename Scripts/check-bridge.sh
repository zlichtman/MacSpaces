#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
# Sources/Core/Bridge holds the files shared byte-for-byte with Tsukumo (including
# MacSpacesAgentsContract.swift). Set TSUKUMO_KEMOSABE_MAC to its macos/KemoSabeMac folder to compare them.
if [[ -n "${TSUKUMO_KEMOSABE_MAC:-}" ]]; then
  for f in MacSpacesBridgeContract.swift LocalBridgeTransport.swift BridgeReceiptStore.swift MacSpacesAgentsContract.swift; do
    cmp -s "Sources/Core/Bridge/$f" "$TSUKUMO_KEMOSABE_MAC/$f" || { echo "$f differs from Tsukumo" >&2; exit 1; }
  done
fi
swiftc -parse-as-library Sources/Core/Bridge/*.swift Sources/Core/Agents/AgentsFixtures.swift Tests/BridgeChecks.swift -o "$check_dir/check-bridge"
"$check_dir/check-bridge"
