#!/bin/bash
# Copies a Feature QA run's website captures into the README and the website.
# Usage: Scripts/publish-demos.sh <feature-qa run id> [--site-only|--readme-only]
#        Scripts/publish-demos.sh --from <folder> [--site-only|--readme-only]   (an already downloaded artifact)
#
# Stills become WebP with `cwebp -q 84 -m 6`. Each output replaces a file that already exists:
#   site/page-<name>.png             -> <name>.webp
#   notch/agents/music.mp4           -> the same name (website only: videos never go in the repo)
#   <video>-poster.png               -> <video>-poster.webp (Music's poster is music.webp)
#   themes-redesign/terminal.png     -> themes-terminal.webp
#   themes-redesign/live.png         -> themes-macspaces.webp
#   themes-redesign/custom-picture.png -> themes-custom.webp
# README copies go to Demos/screenshots only for files the README references. Website copies go to
# PORTFOLIO/public/projects/macspaces/media, and their ?v=<sha256[:12]> hashes in src/app/data.ts are
# updated. Nothing is committed or pushed.
set -euo pipefail
repo=zlichtman/MacSpaces
root=$(cd "$(dirname "$0")/.." && pwd)
portfolio=${PORTFOLIO:-"$root/../../PORTFOLIO"}
media="$portfolio/public/projects/macspaces/media"
data="$portfolio/src/app/data.ts"
readme_dir="$root/Demos/screenshots"

usage() { sed -n 3,4p "$0" | sed 's/^# *//' >&2; exit 2; }
run="" from="" site=1 readme=1
while (($#)); do
  case "$1" in
    --site-only) readme=0 ;;
    --readme-only) site=0 ;;
    --from) from=${2:?}; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) run=$1 ;;
  esac
  shift
done
[[ -n "$run$from" ]] || usage
((site + readme)) || { echo "--site-only and --readme-only together leave nothing to do" >&2; exit 2; }
command -v cwebp > /dev/null || { echo "cwebp is missing: brew install webp" >&2; exit 1; }
if ((site)); then [[ -d "$media" && -f "$data" ]] || { echo "No portfolio at $portfolio (set PORTFOLIO=)" >&2; exit 1; }; fi

work=$(mktemp -d "${TMPDIR:-/tmp}/publish-demos.XXXXXX")
trap 'rm -rf "$work"' EXIT
if [[ -z "$from" ]]; then
  echo "Downloading the feature-qa artifact of run $run"
  gh run download "$run" --repo "$repo" --name feature-qa --dir "$work/artifact"
  from="$work/artifact"
fi
[[ -d "$from" ]] || { echo "No folder $from" >&2; exit 1; }

# Finds an output by its path inside the artifact, wherever the artifact's top folder is.
find_one() { find "$from" -path "*/$1" -type f 2>/dev/null | head -1; }

# source path in the artifact | destination name
pairs=("music-poster.png|music.webp")
while IFS= read -r png; do
  name=$(basename "$png" .png); name=${name#page-}
  pairs+=("site/page-$name.png|$name.webp")
done < <(find "$from" -path '*/site/page-*.png' -type f | sort)
for video in notch agents music wisp ascii; do
  pairs+=("$video.mp4|$video.mp4")
  [[ $video == music ]] && pairs+=("music-poster.png|music.webp") || pairs+=("$video-poster.png|$video-poster.webp")
done
pairs+=("themes-redesign/terminal.png|themes-terminal.webp" "themes-redesign/live.png|themes-macspaces.webp"
        "themes-redesign/custom-picture.png|themes-custom.webp")

hash12() { shasum -a 256 "$1" | cut -c1-12; }
rows=() notes=() done_names=" "
for pair in "${pairs[@]}"; do
  src_rel=${pair%%|*} dest=${pair#*|}
  # Music's poster takes music.webp over a page-music still; a name is only published once.
  [[ "$done_names" == *" $dest "* ]] && { notes+=("$src_rel: skipped, $dest already came from another output"); continue; }
  src=$(find_one "$src_rel")
  [[ -n "$src" ]] || { notes+=("$src_rel: not in the artifact, skipped"); continue; }
  if [[ $dest == *.webp ]]; then
    out="$work/out/$dest"; mkdir -p "$work/out"
    cwebp -quiet -q 84 -m 6 "$src" -o "$out"
  else
    out=$src
  fi
  placed=0
  if ((site)); then
    if [[ -f "$media/$dest" ]]; then
      old=$(hash12 "$media/$dest"); cp "$out" "$media/$dest"; new=$(hash12 "$media/$dest")
      refs=$(grep -c "/projects/macspaces/media/$dest?v=" "$data" || true)
      sed -i '' -E "s#(/projects/macspaces/media/${dest//./\\.})\\?v=[0-9a-f]{12}#\\1?v=$new#g" "$data"
      rows+=("$dest|website|$old|$new|$refs")
      placed=1
    else
      notes+=("$dest: not on the website yet, not added")
    fi
  fi
  if ((readme)) && [[ $dest == *.webp ]]; then
    if grep -q "Demos/screenshots/$dest" "$root/README.md"; then
      old=$( [[ -f "$readme_dir/$dest" ]] && hash12 "$readme_dir/$dest" || echo "(new)")
      cp "$out" "$readme_dir/$dest"
      rows+=("$dest|README|$old|$(hash12 "$readme_dir/$dest")|-")
      placed=1
    elif ((!site)); then
      notes+=("$dest: the README doesn't use it, skipped")
    fi
  fi
  ((placed)) && done_names+="$dest "
done

if ((${#rows[@]})); then
  { echo "FILE|COPY|OLD|NEW|DATA.TS REFS"; printf '%s\n' "${rows[@]}"; } | column -t -s '|'
  unchanged=$(printf '%s\n' "${rows[@]}" | awk -F'|' '$3 == $4' | wc -l | tr -d ' ')
  ((unchanged)) && echo "($unchanged unchanged: same bytes as before)"
else
  echo "Nothing was replaced."
fi
((${#notes[@]})) && { echo; echo "Notes:"; printf '  %s\n' "${notes[@]}"; }
echo
echo "Not committed. Review with: git -C \"$root\" status; git -C \"$portfolio\" status"
