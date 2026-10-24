#!/bin/bash
# Releases the version in project.yml from start to finish, in order:
#   checks → new root commit "MacSpaces X.Y" (force-with-lease) → notarized installer
#   and CI in parallel → tag → GitHub release → Homebrew cask → delete older releases.
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
for check in check-release-policy check-update-revisions check-core check-appearance check-settings-search check-power-helper; do
  ./Scripts/$check.sh | tail -1
done

step 'Root commit'
remote=$(git ls-remote origin refs/heads/main | cut -f1)
git add -A
message="MacSpaces $version"
[[ -n "${SHIP_TRAILER:-}" ]] && message+=$'\n\n'"$SHIP_TRAILER"
commit=$(printf '%s\n' "$message" | git commit-tree "$(git write-tree)")
git update-ref refs/heads/main "$commit"
git push --force-with-lease="main:$remote" origin main
echo "main is $commit"

step 'Installer and CI (in parallel)'
make release > "$logs/release.log" 2>&1 &
release_pid=$!
# `gh run list --commit` matches only a full SHA.
until run=$(gh run list --repo "$repo" --commit "$commit" --limit 1 --json databaseId --jq '.[0].databaseId') && [[ -n "$run" ]]; do
  sleep 10
done
# Poll the run rather than `gh run watch`, which exits on a passing GitHub API error (a 502
# stopped 3.3's release while CI was still running); only CI's own conclusion counts.
until status=$(gh api "repos/$repo/actions/runs/$run" --jq '"\(.status) \(.conclusion)"' 2>/dev/null) && [[ "$status" == completed* ]]; do
  sleep 20
done
ci_ok=1
[[ "$status" == "completed success" ]] || ci_ok=0
release_ok=1
wait "$release_pid" || release_ok=0
tail -2 "$logs/release.log"
[[ $release_ok == 1 ]] || { echo "Installer failed; log: $logs/release.log" >&2; exit 1; }
[[ $ci_ok == 1 ]] || { echo "CI failed: https://github.com/$repo/actions/runs/$run" >&2; exit 1; }
echo 'CI passed'

step 'Tag and publish'
git tag -f "$tag" "$commit"
git push origin "$tag"
./Scripts/publish-release.sh 2>&1 | grep -v deprecated | tail -1
sha=$(shasum -a 256 Releases/MacSpaces.dmg | awk '{print $1}')

step 'Homebrew cask'
git -C "$tap" pull --ff-only -q
sed -i '' -E -e "s/^  version \".*\"/  version \"$version\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$tap/Casks/macspaces.rb"
brew style --cask "$tap/Casks/macspaces.rb" | tail -1
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

step "Shipped MacSpaces $version: https://github.com/$repo/releases/tag/$tag"
