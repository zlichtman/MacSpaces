#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"; rm -f "$HOME/Library/Preferences/dev.opensource.MacSpaces.TapeChecks.plist"' EXIT
# Tape's settings read their keys from WidgetOptions.Keys, whose file needs most of the app.
{
  echo 'enum WidgetOptions { enum Keys {'
  grep -E '^ *static let tape[A-Z][A-Za-z]* = "tape\.' Sources/Modules/Notch/Settings/WidgetOptions.swift
  echo '} }'
} > "$check_dir/TapeKeys.swift"
swiftc -parse-as-library Sources/Modules/Tape/Engine/*.swift Sources/Modules/Tape/Platform/*.swift \
  Sources/Core/Spaces/SpaceLayout.swift Sources/Services/ManagedSpaces.swift \
  Sources/Modules/Tape/TapeController.swift Sources/Modules/Tape/TapeSettings.swift \
  "$check_dir/TapeKeys.swift" Tests/TapeChecks.swift -o "$check_dir/check-tape"
"$check_dir/check-tape"
