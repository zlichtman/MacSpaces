#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/check-release-policy.sh
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit the final snapshot before publishing.' >&2; exit 1; }
repo=zlichtman/MacSpaces
commit=$(git rev-parse HEAD)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Resources/Info.plist)
staging=$(mktemp -d)
trap 'hdiutil detach "$staging/mount" >/dev/null 2>&1 || true; rm -rf "$staging"' EXIT

git ls-remote --heads --tags origin > "$staging/refs"
gh api "repos/$repo/releases" > "$staging/releases.json"
gh run list --repo "$repo" --workflow ci.yml --commit "$commit" --limit 20 --json headSha,conclusion > "$staging/ci.json"
python3 - "$staging" "$commit" "$build" <<'PY'
import json, re, sys
from pathlib import Path
root, commit, build = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
refs = dict(line.split()[::-1] for line in (root/'refs').read_text().splitlines())
assert refs == {'refs/heads/main':commit, 'refs/tags/v1.0.0':commit}, 'Publish only the sole main snapshot and v1.0.0 tag'
releases = json.loads((root/'releases.json').read_text())
assert len(releases) == 1 and releases[0]['tag_name'] == 'v1.0.0', 'Exactly one existing v1.0.0 release is required'
release = releases[0]
assert not release['draft'] and not release['prerelease']
markers = re.findall(r'^<!-- macspaces-build:([0-9]+) -->$', release.get('body') or '', re.M)
assert len(markers) == 1 and build > int(markers[0]), 'Increment the internal build before replacing the installer'
runs = json.loads((root/'ci.json').read_text())
assert any(run['headSha'] == commit and run['conclusion'] == 'success' for run in runs), 'CI must pass on the exact snapshot'
notes = Path('RELEASE_NOTES.md').read_text().rstrip()
assert 'macspaces-build:' not in notes, 'The publisher manages the build marker'
(root/'notes.md').write_text(f'{notes}\n\n<!-- macspaces-build:{build} -->\n')
PY

mkdir "$staging/mount"
hdiutil attach Releases/MacSpaces.dmg -nobrowse -readonly -mountpoint "$staging/mount" >/dev/null
app="$staging/mount/MacSpaces.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == '1.0.0' ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$build" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == dev.opensource.MacSpaces ]]
codesign --verify --deep --strict "$app"
codesign -dv --verbose=4 "$app" 2>&1 | grep -qx 'TeamIdentifier=28LJG7MXT3'
xcrun stapler validate "$app"
xcrun stapler validate Releases/MacSpaces.dmg
spctl --assess --type execute "$app"
spctl --assess --type open --context context:primary-signature Releases/MacSpaces.dmg
architectures=$(lipo -archs "$app/Contents/MacOS/MacSpaces")
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
hdiutil detach "$staging/mount" >/dev/null

gh release upload v1.0.0 Releases/MacSpaces.dmg --repo "$repo" --clobber
gh release edit v1.0.0 --repo "$repo" --title 'MacSpaces 1.0.0' --notes-file "$staging/notes.md" --target "$commit" --latest
expected_digest="sha256:$(shasum -a 256 Releases/MacSpaces.dmg | awk '{print $1}')"
actual_digest=$(gh api "repos/$repo/releases/tags/v1.0.0" --jq '.assets[] | select(.name == "MacSpaces.dmg") | .digest')
[[ "$actual_digest" == "$expected_digest" ]] || { echo 'Published installer checksum differs.' >&2; exit 1; }
echo 'Updated the single MacSpaces 1.0.0 release.'
