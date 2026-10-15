#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -parse-as-library Sources/Core/Media/*.swift \
  Sources/Services/NowPlaying/NowPlayingInfo.swift \
  Sources/Services/NowPlaying/AppleScriptProvider.swift \
  Sources/Services/NowPlaying/MediaRemoteProvider.swift \
  Sources/Services/NowPlaying/BrowserMediaProvider.swift \
  Sources/Services/NowPlaying/ArtworkLookup.swift \
  Sources/Services/NowPlaying/SpotifyCovers.swift \
  Sources/Services/AppleScriptRunner.swift Tests/PlaybackChecks.swift -o "$check_dir/check-playback"
"$check_dir/check-playback"
