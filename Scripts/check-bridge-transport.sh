#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage=$(mktemp -d /private/tmp/macspaces-bridge-test.XXXXXX)
trap 'if [[ -n "${server_pid:-}" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi; rm -rf "${stage:?}"' EXIT
swiftc -parse-as-library Sources/Core/Bridge/MacSpacesBridgeContract.swift Sources/Core/Bridge/LocalBridgeTransport.swift Tests/BridgeTransportChecks.swift -o "$stage/server"
cp "$stage/server" "$stage/client"
cp "$stage/server" "$stage/wrong-client"
identity=${MACSPACES_TEST_SIGNING_IDENTITY:?Set a signing identity from team 28LJG7MXT3}
codesign --force --sign "$identity" --identifier com.zlichtman.kemosabe.mac "$stage/server"
codesign --force --sign "$identity" --identifier dev.opensource.MacSpaces "$stage/client"
codesign --force --sign "$identity" --identifier dev.opensource.MacSpaces.UntrustedTest "$stage/wrong-client"
# Redacted server diagnostics (stage names only) go to a log the checks below read.
"$stage/server" server "$stage/endpoint" 2>"$stage/server.log" &
server_pid=$!
for i in {1..50}; do [[ -f "$stage/endpoint.ready" ]] && break; sleep 0.1; done
[[ -f "$stage/endpoint.ready" ]] || { echo "Fixture server did not start"; exit 1; }
# The expected peer, several times: a race between the two signature checks must not drop it.
for i in 1 2 3 4 5; do "$stage/client" client "$stage/endpoint"; done
"$stage/client" delayed "$stage/endpoint"
"$stage/wrong-client" rejected "$stage/endpoint"
sleep 0.5
cat "$stage/server.log"
[[ $(grep -c "server replied" "$stage/server.log") -eq 6 ]] || { echo "Expected six authenticated replies"; exit 1; }
[[ $(grep -c "stage=identity" "$stage/server.log") -eq 1 ]] || { echo "Wrong identity was not rejected at the identity stage"; exit 1; }
! grep -q "stage=request\|stage=reply\|stage=write" "$stage/server.log" || { echo "A signed peer failed after authentication"; exit 1; }
echo "Bridge transport checks passed: signed peer x5, delayed writer, wrong identity rejected at the identity stage"
