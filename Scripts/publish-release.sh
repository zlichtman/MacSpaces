#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/check-release-policy.sh
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit the final snapshot before publishing.' >&2; exit 1; }
repo=zlichtman/MacSpaces
commit=$(git rev-parse HEAD)
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Resources/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Resources/Info.plist)
tag="v$version"
staging=$(mktemp -d)
trap 'hdiutil detach "$staging/mount" >/dev/null 2>&1 || true; rm -rf "$staging"' EXIT

git ls-remote --heads --tags origin > "$staging/refs"
gh api "repos/$repo/releases?per_page=100" > "$staging/releases.json"
gh run list --repo "$repo" --workflow ci.yml --commit "$commit" --limit 20 --json headSha,conclusion > "$staging/ci.json"
python3 - "$staging" "$commit" "$build" "$tag" <<'PY'
import json, re, sys
from pathlib import Path
root, commit, build, tag = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3]), sys.argv[4]
refs = dict(line.split()[::-1] for line in (root/'refs').read_text().splitlines())
assert refs.get('refs/heads/main') == commit, 'Publish the commit at the tip of main'
tagged = refs.get(f'refs/tags/{tag}^{{}}', refs.get(f'refs/tags/{tag}'))
assert tagged == commit, f'Push {tag} at the current main commit before publishing'
releases = [release for release in json.loads((root/'releases.json').read_text()) if not release['draft']]
builds = []
for release in releases:
    markers = re.findall(r'^<!-- macspaces-build:([0-9]+) -->$', release.get('body') or '', re.M)
    assert len(markers) == 1, f"Release {release['tag_name']} needs exactly one build marker"
    builds.append(int(markers[0]))
assert not builds or build > max(builds), 'Increment the internal build above every published release'
existing = [release for release in releases if release['tag_name'] == tag]
assert len(existing) <= 1 and not any(release['prerelease'] for release in existing)
(root/'mode').write_text('update' if existing else 'create')
runs = json.loads((root/'ci.json').read_text())
assert any(run['headSha'] == commit and run['conclusion'] == 'success' for run in runs), 'CI must pass on the exact commit'
notes = Path('RELEASE_NOTES.md').read_text().rstrip()
assert 'macspaces-build:' not in notes, 'The publisher manages the build marker'
(root/'notes.md').write_text(f'{notes}\n\n<!-- macspaces-build:{build} -->\n')
PY

mkdir "$staging/mount"
hdiutil attach Releases/MacSpaces.dmg -nobrowse -readonly -mountpoint "$staging/mount" >/dev/null
app="$staging/mount/MacSpaces.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
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

if [[ "$(cat "$staging/mode")" == update ]]; then
  gh release upload "$tag" Releases/MacSpaces.dmg --repo "$repo" --clobber
  gh release edit "$tag" --repo "$repo" --title "MacSpaces $version" --notes-file "$staging/notes.md" --latest
else
  gh release create "$tag" Releases/MacSpaces.dmg --repo "$repo" --title "MacSpaces $version" \
    --notes-file "$staging/notes.md" --verify-tag --latest
fi
expected_digest="sha256:$(shasum -a 256 Releases/MacSpaces.dmg | awk '{print $1}')"
actual_digest=$(gh api "repos/$repo/releases/tags/$tag" --jq '.assets[] | select(.name == "MacSpaces.dmg") | .digest')
[[ "$actual_digest" == "$expected_digest" ]] || { echo 'Published installer checksum differs.' >&2; exit 1; }
echo "Published MacSpaces $version (build $build)."
