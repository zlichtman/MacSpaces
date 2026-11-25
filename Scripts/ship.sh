#!/bin/bash
# Releases the version in project.yml from start to finish, in order:
#   preflight (build and every check) → new root commit "MacSpaces X.Y" (force-with-lease) →
#   notarized installer → tag → GitHub release → Homebrew cask → delete older releases.
# It doesn't wait for CI, which repeats preflight's checks and compile on GitHub and takes about
# 13 minutes: a failure there is fixed in the next release. SHIP_WAIT_CI=1 waits for its pass.
# Extra lines for the commit message (e.g. a Co-Authored-By trailer) go in SHIP_TRAILER.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=zlichtman/MacSpaces
tap="$(brew --repository)/Library/Taps/zlichtman/homebrew-tap"
logs=$(mktemp -d)

step() { printf '\n==> %s\n' "$*"; }

[[ "$(git branch --show-current)" == main ]] || { echo 'Ship from main.' >&2; exit 1; }
xcodegen generate --spec project.yml --project . --project-root . >/dev/null
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Resources/Info.plist)
tag="v$version"
step "MacSpaces $version"

step 'Checks'
# Preflight runs every check script, the release policy and settings compatibility among them.
./Scripts/preflight.sh | tail -1

step 'Root commit'
# Another session may be working in this folder: its new files are never swept into a release.
stray=$(git ls-files --others --exclude-standard)
[[ -z "$stray" ]] || { printf 'Files not in git (another session'"'"'s work?); add or move them first:\n%s\n' "$stray" >&2; exit 1; }
remote=$(git ls-remote origin refs/heads/main | cut -f1)
git add -A
message="MacSpaces $version"
[[ -n "${SHIP_TRAILER:-}" ]] && message+=$'\n\n'"$SHIP_TRAILER"
commit=$(printf '%s\n' "$message" | git commit-tree "$(git write-tree)")
git update-ref refs/heads/main "$commit"
git push --force-with-lease="main:$remote" origin main
echo "main is $commit"

step 'Installer'
# CI runs on the pushed commit alongside the installer build. With SHIP_WAIT_CI=1 publishing
# needs its pass (publish-release.sh checks it), and the wait overlaps notarization.
export SHIP_WAIT_CI="${SHIP_WAIT_CI:-0}"
# With the screen locked preflight leaves check-notes to CI, so then the release waits for CI.
if [[ "$SHIP_WAIT_CI" != 1 && "$(ioreg -n Root -d1 -k IOConsoleUsers 2> /dev/null | grep -c '"CGSSessionScreenIsLocked"=Yes' || true)" != 0 ]]; then
  echo 'The screen is locked, so check-notes was left to CI: waiting for CI.'
  SHIP_WAIT_CI=1
fi
started=$SECONDS
make release > "$logs/release.log" 2>&1 &
release_pid=$!
if [[ "$SHIP_WAIT_CI" == 1 ]]; then
  # `gh run list --commit` matches only a full SHA.
  until run=$(gh run list --repo "$repo" --commit "$commit" --limit 1 --json databaseId --jq '.[0].databaseId') && [[ -n "$run" ]]; do
    sleep 10
  done
  # Poll the run rather than `gh run watch`, which exits on a passing GitHub API error.
  until status=$(gh api "repos/$repo/actions/runs/$run" --jq '"\(.status) \(.conclusion)"' 2>/dev/null) && [[ "$status" == completed* ]]; do
    sleep 20
  done
  [[ "$status" == "completed success" ]] || { echo "CI failed: https://github.com/$repo/actions/runs/$run" >&2; wait "$release_pid" || true; exit 1; }
  echo 'CI passed'
fi
release_ok=1
wait "$release_pid" || release_ok=0
tail -2 "$logs/release.log"
echo "installer took $((SECONDS - started)) s"
[[ $release_ok == 1 ]] || { echo "Installer failed; log: $logs/release.log" >&2; exit 1; }

step 'Tag and publish'
git tag -f "$tag" "$commit"
# A run that stopped after tagging leaves the tag on GitHub with no release; replace it then, never
# when that version is already published.
if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null && ! gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  git push --force origin "$tag"
else
  git push origin "$tag"
fi
./Scripts/publish-release.sh 2>&1 | grep -v deprecated | tail -1
sha=$(shasum -a 256 Releases/MacSpaces.dmg | awk '{print $1}')

step 'Homebrew cask'
git -C "$tap" pull --ff-only -q
sed -i '' -E -e "s/^  version \".*\"/  version \"$version\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$tap/Casks/macspaces.rb"
brew style zlichtman/tap/macspaces 2>&1 | tail -1
if ! git -C "$tap" diff --quiet; then
  git -C "$tap" commit -q -am "Update MacSpaces to $version"
  git -C "$tap" push -q origin HEAD
fi
echo "cask is $version"

step 'Older releases'
# GitHub keeps only the current release (and its tag). Deleting a release deletes its download
# count too, so each count goes into downloads.tsv first (git-ignored; the only record).
[[ -f downloads.tsv ]] || printf 'release\tdownloads\tdeleted\n' > downloads.tsv
for old in $(gh release list --repo "$repo" --limit 100 --json tagName --jq '.[].tagName'); do
  [[ "$old" == "$tag" ]] && continue
  count=$(gh release view "$old" --repo "$repo" --json assets --jq '[.assets[].downloadCount] | add // 0') ||
    { echo "kept $old: its download count couldn't be read" >&2; continue; }
  if gh release delete "$old" --repo "$repo" --cleanup-tag -y; then
    printf '%s\t%s\t%s\n' "$old" "$count" "$(date +%F)" >> downloads.tsv
    echo "deleted $old ($count downloads)"
  fi
done
for old in $(git tag --list 'v*'); do
  [[ "$old" == "$tag" ]] || git tag -d "$old" >/dev/null
done
./Scripts/downloads.sh | tail -1

[[ "$SHIP_WAIT_CI" == 1 ]] || echo "CI is still running on this commit: https://github.com/$repo/commit/$commit/checks"
step "Shipped MacSpaces $version in $((SECONDS / 60)) min: https://github.com/$repo/releases/tag/$tag"
