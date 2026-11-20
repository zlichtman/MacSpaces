#!/bin/bash
# Prints MacSpaces' download counts: each deleted release from downloads.tsv (ship.sh records
# it before deleting the release, since GitHub drops the count with it), the current release
# live from GitHub, then the total. The installer, Homebrew and the in-app updater all download
# MacSpaces.dmg, so these are downloads, not people.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=zlichtman/MacSpaces
{
  [[ -f downloads.tsv ]] && tail -n +2 downloads.tsv | cut -f1,2
  gh release view --repo "$repo" --json tagName,assets --jq '"\(.tagName) (current)\t\([.assets[].downloadCount] | add // 0)"'
} | awk -F'\t' '{ print; total += $2 } END { print "all releases\t" total + 0 }' | column -t -s $'\t'
