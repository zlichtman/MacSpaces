#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Core/Media/Lyrics.swift Sources/Core/Media/MoodTreatment.swift Sources/Core/Media/LyricSubject.swift \
  Sources/Core/Media/StickerMatch.swift \
  Sources/Services/LyricsCache.swift \
  Tests/LyricsChecks.swift -o "$check_dir/check-lyrics"
"$check_dir/check-lyrics"
