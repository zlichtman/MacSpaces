#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Services/Messaging/IncomingMessagesReader.swift Sources/Services/Messaging/SystemNotificationsReader.swift Tests/IncomingMessagesChecks.swift -o "$check_dir/check-incoming"
"$check_dir/check-incoming"
# Other apps' databases (Messages, Notification Center, Maccy) are only ever opened read-only:
# MacSpaces never writes chat.db or anyone else's store.
if grep -rn "sqlite3_open" Sources | grep -v "SQLITE_OPEN_READONLY"; then
  echo "A database is opened without SQLITE_OPEN_READONLY" >&2; exit 1
fi
echo "Every database is opened read-only"
