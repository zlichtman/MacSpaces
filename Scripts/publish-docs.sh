#!/bin/bash
# Publishes a documentation-only update without a new installer (release policy: a docs-only
# change replaces the single root commit and moves the current version's tag to it).
# Takes README.md, AGENTS.md, Demos/ and docs/ from the working tree (and a deleted CHANGELOG.md); refuses if anything else would change
# from the published commit. Extra lines for the commit message go in SHIP_TRAILER.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Resources/Info.plist)
tag="v$version"
remote=$(git ls-remote origin refs/heads/main | cut -f1)
tagged=$(git ls-remote origin "refs/tags/$tag" | cut -f1)
[[ -n "$remote" && "$remote" == "$tagged" ]] || { echo "main and $tag differ on GitHub; ship a release instead." >&2; exit 1; }
git fetch -q origin main

# Start from the published tree and take only the docs from the working tree.
index=$(mktemp); trap 'rm -f "$index"' EXIT
export GIT_INDEX_FILE="$index"
git read-tree "$remote"
git add README.md AGENTS.md Demos docs
git add -u Demos docs
[[ -e CHANGELOG.md ]] || git rm -q --cached --ignore-unmatch CHANGELOG.md
tree=$(git write-tree)
unset GIT_INDEX_FILE
changed=$(git diff --name-only "$remote" "$tree")
[[ -n "$changed" ]] || { echo 'No documentation changes.'; exit 0; }
if grep -v -E '^(README\.md|AGENTS\.md|CHANGELOG\.md|Demos/|docs/)' <<< "$changed"; then
  echo 'Those files are not documentation; ship a release instead.' >&2; exit 1
fi
echo "$changed" | sed 's/^/  /'

message="MacSpaces $version"
# A docs-only publish changes no code: this body line keeps CI from re-running on it.
message+=$'\n\n[skip ci]'
[[ -n "${SHIP_TRAILER:-}" ]] && message+=$'\n\n'"$SHIP_TRAILER"
commit=$(printf '%s\n' "$message" | git commit-tree "$tree")
git push --force-with-lease="main:$remote" origin "$commit:refs/heads/main"
git push --force-with-lease="refs/tags/$tag:$remote" origin "$commit:refs/tags/$tag"
# The tag follows. Local main follows only when it had nothing unpublished; otherwise its
# commits stay where they are (the next release builds a fresh root from the working tree).
git tag -f "$tag" "$commit" >/dev/null
if [[ "$(git rev-parse main)" == "$remote" ]]; then
  git update-ref refs/heads/main "$commit"
  git reset -q
fi
echo "Published docs for MacSpaces $version: main and $tag are $commit (installer unchanged)."
