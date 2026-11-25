#!/bin/bash
# To-dos written in notes: the marks (estimate, priority, time), ticking a line, adding one and the day's order;
# and a linked Markdown file, ticked and added to for real in a temporary folder.
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Core/Persistence/NoteTasks.swift Sources/Services/TodoFile.swift Tests/NoteTaskChecks.swift -o "$check_dir/check-tasks"
"$check_dir/check-tasks"
