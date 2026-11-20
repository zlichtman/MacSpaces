#!/bin/bash
# Timed, isolated, native window capture. No manual clicks or timing; no publication.
# Usage: Scripts/capture-demos.sh [--all|--music-only|--stills-only|--videos|--test] [--output /absolute/folder] [--check|--retry|--clean]
# The default (--all) makes every still and video the site shows; --videos only the videos and Tools images;
# --stills-only only stills (no video is recorded, so none is replaced).
# --test records a few clips to the output folder only: a quick check that recording works. Nothing is copied to the site or README.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mode=all
mode_explicit=0
keep_build=0
retry=0
output=""
check=0
clean=0
while (($#)); do
  case "$1" in
    --all) mode=all; mode_explicit=1 ;;
    --clean) clean=1 ;;
    --help|-h) echo "Usage: $0 [--all|--music-only|--stills-only] [--output /absolute/folder] [--check|--retry|--clean]"; exit 0 ;;
    --music-only) mode=music; mode_explicit=1 ;;
    --stills-only) mode=stills; mode_explicit=1 ;;
    --test) mode=test; mode_explicit=1 ;;
    --videos) mode=videos; mode_explicit=1 ;;
    --output) output=${2:?}; shift ;;
    --check) check=1 ;;
    --retry) retry=1 ;;
    --keep-build) keep_build=1 ;;
    *) echo "Usage: $0 [--music-only|--stills-only] [--output /absolute/folder] [--check]" >&2; exit 2 ;;
  esac
  shift
done
if ((clean)); then
  [[ -n "$output" && -f "$output/.capture-work" ]] || { echo "--clean needs --output with a retained capture build" >&2; exit 2; }
  [[ ! -d "${TMPDIR:-/tmp}/macspaces-native-demo.lock" ]] || { echo "Wait for the active capture to finish before cleaning." >&2; exit 75; }
  work=$(cat "$output/.capture-work")
  python3 - "$work" <<'PYTHON'
import pathlib,re,sys,tempfile
p=pathlib.Path(sys.argv[1]).resolve()
assert p.parent==pathlib.Path(tempfile.gettempdir()).resolve() and re.fullmatch(r'macspaces-native-demo\.[A-Za-z0-9]{6}',p.name), 'Invalid capture build path'
PYTHON
  rm -rf "$work" "$output/raw"
  rm -f "$output/.capture-work"
  echo "Removed this capture's temporary build and raw frames; exported files remain in $output."
  exit 0
fi
for tool in python3 xcrun xcodegen ffmpeg ffprobe cwebp; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. Install prerequisites with: brew install xcodegen ffmpeg webp" >&2; exit 1; }
done
python3 - "$root/Demos/music-sequence.json" <<'PY'
import json, sys
s=json.load(open(sys.argv[1]))
assert len(s['songs']) == 5 and len({x['key'] for x in s['songs']}) == 5
for i,x in enumerate(s['songs'],1): print(f"{i}. {x['artist']} — {x['title']} ({x['theme']})")
PY
((check)) && { echo "Capture tools and sequence are ready. Screen Recording permission is checked when capture starts."; exit 0; }
# A locked desktop cannot supply native frames. Stop before downloading or building.
desktop_is_locked() {
  local session_state
  session_state=$(ioreg -n Root -d1 -k IOConsoleUsers)
  [[ "$session_state" == *'"CGSSessionScreenIsLocked"=Yes'* ]]
}
if desktop_is_locked; then
  echo "The Mac is locked. Unlock the desktop, then rerun this command; no manual demo timing is needed." >&2
  exit 75
fi
# A second capture must never compete for the same display or encoder.
lock="${TMPDIR:-/tmp}/macspaces-native-demo.lock"
mkdir "$lock" 2>/dev/null || { echo "A capture is already running ($lock)." >&2; exit 75; }
work=""
app_pid=""
awake_pid=""
cleanup() {
  status=$?
  if [[ -n "$awake_pid" ]]; then kill "$awake_pid" 2>/dev/null || true; fi
  if [[ -n "$work" ]]; then pkill -TERM -f "^$work/record-window( |$)" 2>/dev/null || true; fi
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then pkill -TERM -P "$app_pid" 2>/dev/null || true; kill "$app_pid" 2>/dev/null || true; fi
  if [[ "$status" == 0 && "$keep_build" == 0 ]]; then
    [[ -z "$work" ]] || rm -rf "$work"
    rm -f "$output/.capture-work"
  elif [[ -n "$work" && -d "$work" ]]; then
    printf '%s\n' "$work" > "$output/.capture-work"
    echo "Temporary capture build retained. Retry without rebuilding: Scripts/capture-demos.sh --retry --output \"$output\"" >&2
  fi
  rmdir "$lock" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM
[[ -n "$output" ]] || output="${TMPDIR:-/tmp}/MacSpaces-captures-$(date +%Y%m%d-%H%M%S)"
[[ "$output" == /* ]] || { echo "--output must be absolute" >&2; exit 2; }
mkdir -p "$output"
# Refuse to mix an earlier run's movies and new stills.
if ((retry)); then
  [[ -f "$output/.capture-work" ]] || { echo "No capture build to retry in $output" >&2; exit 2; }
  work=$(cat "$output/.capture-work")
  [[ "$work" == *"/macspaces-native-demo."* && -d "$work" ]] || { echo "Invalid retry directory" >&2; exit 2; }
  ((mode_explicit)) || mode=$(cat "$work/mode")
  rm -rf "$output/raw"
else
  [[ ! -e "$output/capture.json" && ! -e "$output/raw" && ! -e "$output/.capture-work" ]] || { echo "Choose an empty output folder." >&2; exit 2; }
  work=$(mktemp -d "${TMPDIR:-/tmp}/macspaces-native-demo.XXXXXX")
  printf '%s\n' "$mode" > "$work/mode"
fi
# Keep this short capture session visible without changing the owner's settings.
caffeinate -d -i -w $$ >/dev/null 2>&1 &
awake_pid=$!
mac-status
line=$(mac-status 2>/dev/null | sed -n '/^free:/p')
free=$(sed -nE 's/^free: ([0-9]+)%.*/\1/p' <<< "$line")
swap=$(sed -nE 's/.*swap ([0-9.]+)([MG]).*/\1 \2/p' <<< "$line" | awk '{print ($2 == "G") ? $1 * 1024 : $1}')
[[ -n "$free" && -n "$swap" ]] || { echo "Cannot verify shared Mac memory; stop before building." >&2; exit 75; }
if [[ "$free" -lt 40 ]] || awk "BEGIN {exit !($swap > 6144)}" || pgrep -x xcodebuild >/dev/null; then
  echo "Wait for memory/build capacity ($line)." >&2; exit 75
fi
# Assets and build caches live outside iCloud; success removes them, failure supports --retry.
python3 "$root/Scripts/demo/prepare-music.py" "$root/Demos/music-sequence.json" "$work/assets"
xcrun swiftc -parse-as-library -O -module-cache-path "$work/modules" "$root/Scripts/demo/record-window.swift" -o "$work/record-window" > "$output/recorder-build.log" 2>&1
"$work/record-window" --check
fingerprint=$(python3 - "$root" <<'PYTHON'
import hashlib,pathlib,sys
root=pathlib.Path(sys.argv[1]); h=hashlib.sha256()
for p in sorted(root.joinpath('Sources').rglob('*.swift')) + [root/'project.yml']:
    h.update(str(p.relative_to(root)).encode()); h.update(p.read_bytes())
print(h.hexdigest())
PYTHON
)
if [[ ! -x "$work/build/Build/Products/Debug/MacSpaces.app/Contents/MacOS/MacSpaces" || ! -f "$work/source.sha256" || "$(cat "$work/source.sha256")" != "$fingerprint" ]]; then
  # Preserve SRCROOT-relative plist and entitlement paths without copying project sources.
  [[ -e "$work/Sources" ]] || ln -s "$root/Sources" "$work/Sources"
  [[ -e "$work/Helpers" ]] || ln -s "$root/Helpers" "$work/Helpers"
  xcodegen generate --spec "$root/project.yml" --project "$work" --quiet
  xcodebuild -project "$work/MacSpaces.xcodeproj" -scheme MacSpaces -configuration Debug -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$work/build" -clonedSourcePackagesDirPath "$work/packages" \
    -skipPackagePluginValidation -jobs 2 -quiet ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    PRODUCT_BUNDLE_IDENTIFIER=dev.opensource.MacSpaces.WebsiteDemo CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
    SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule GCC_OPTIMIZATION_LEVEL=s \
    build > "$output/build.log" 2>&1
  printf '%s\n' "$fingerprint" > "$work/source.sha256"
fi
# The agents' App Store icons for the hero reel's Agents tab (never committed); without them it draws plain marks.
mkdir -p "$work/assets/agent-icons"
for pair in claude:com.anthropic.claude codex:com.openai.chat; do
  icon_url=$(curl -sf "https://itunes.apple.com/lookup?bundleId=${pair#*:}" | python3 -c "import json,sys; print(json.load(sys.stdin)['results'][0]['artworkUrl512'].rsplit('/', 1)[0] + '/1024x1024bb.png')" 2>/dev/null || true)
  [[ -z "$icon_url" ]] || curl -sfL -o "$work/assets/agent-icons/${pair%%:*}.png" "$icon_url" || true
done
python3 - "$work/assets/tracks.json" "$output/tracks-provenance.json" <<'PYTHON'
import json,sys
tracks=json.load(open(sys.argv[1]))
for track in tracks.values(): track.pop('cover',None)
json.dump(tracks,open(sys.argv[2],'w'),indent=2)
PYTHON
raw="$output/raw"; mkdir -p "$raw"
clips=$(python3 - "$root/Demos/music-sequence.json" "$mode" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); mode=sys.argv[2]
clips=[] if mode in ('stills','test') else ['music-showcase','music-terminal']
clips += [f"music-{i:02d}-{song['key']}" for i,song in enumerate(s['songs'],1)]
if mode=='test':
    clips = ['music-01-'+s['songs'][0]['key'],'music-terminal','tour','page-music-terminal','page-timers','tape']
else:
    # The videos and stills only --videos and the default run make; the default run makes everything the site shows.
    # --stills-only records no video at all, so it can never replace a published one.
    extra = ['calendar-life','clock-match','page-homebrew','kemosabe-sarah','tape','reel']
    if mode=='videos':
        clips += ['tour'] + extra
    elif mode!='music':
        clips += (['tour','themes','ascii'] if mode=='all' else [])
        clips += ['page-music-tint','page-music-terminal','page-music-devices','page-theme-terminal','page-theme-terminal-light'] + ['page-'+x for x in ['home','music','calendar','timers','notes','prompter','coding','usage','shortcuts','tray','weather','clock','system','meetings','dictation','wisp-hello','wisp','ascii']]
        # Heartable's views and Folio's library, viewer, search, Colors and Links.
        clips += ['page-'+x for x in ['stats','backups','backup-compare','shelf'] + ['folio-'+f for f in ['library','board','viewer','search','colors','links']]]
        if mode=='all': clips += extra
print(','.join(clips))
PY
)
if desktop_is_locked; then
  echo "The Mac locked during preparation. Unlock it and use --retry with this output folder." >&2
  exit 75
fi
echo "Capture is automatic. A clean MacSpaces demo window will appear; leave it on screen until it closes."
echo "If macOS asks for Screen Recording, allow the capture terminal and rerun this command."
profile=$(mktemp -d "$work/profile.XXXXXX")
MACSPACES_DEMO_FIXTURE_ROOT="$profile" TMPDIR="$profile/" TZ=America/Chicago NSUnbufferedIO=YES MACSPACES_WEBSITE_DEMO=1 MACSPACES_DEMO_KIND=clips \
MACSPACES_DEMO_LOCAL=1 MACSPACES_DEMO_SCALE=1 MACSPACES_DEMO_FPS=60 \
MACSPACES_DEMO_SEQUENCE="$root/Demos/music-sequence.json" MACSPACES_DEMO_TRACKS="$work/assets/tracks.json" \
MACSPACES_DEMO_RECORDER="$work/record-window" MACSPACES_DEMO_CLIPS="$clips" MACSPACES_DEMO_OUTPUT="$raw" MACSPACES_DEMO_AGENT_ICONS="$work/assets/agent-icons" \
  "$work/build/Build/Products/Debug/MacSpaces.app/Contents/MacOS/MacSpaces" > "$output/capture.log" 2>&1 &
app_pid=$!
wait "$app_pid"
app_pid=""
rm -rf "$profile"
python3 "$root/Scripts/demo/export-captures.py" "$root/Demos/music-sequence.json" "$output" "$mode" "$work/record-window"
if [[ $mode == videos || $mode == all ]]; then
  # The Agents and Pop-outs videos are drawn frame by frame, on the site's page colour.
  for story in agents popouts; do
    profile=$(mktemp -d "$work/profile.XXXXXX")
    MACSPACES_DEMO_FIXTURE_ROOT="$profile" TMPDIR="$profile/" TZ=America/Chicago NSUnbufferedIO=YES MACSPACES_WEBSITE_DEMO=1 MACSPACES_DEMO_KIND=agents \
    MACSPACES_DEMO_LOCAL=1 MACSPACES_DEMO_PLAIN=1 MACSPACES_DEMO_STORY="$story" MACSPACES_DEMO_HERO_THEME=thunderstorm \
    MACSPACES_DEMO_SEQUENCE="$root/Demos/music-sequence.json" MACSPACES_DEMO_TRACKS="$work/assets/tracks.json" MACSPACES_DEMO_OUTPUT="$output/$story" \
      "$work/build/Build/Products/Debug/MacSpaces.app/Contents/MacOS/MacSpaces" >> "$output/capture.log" 2>&1
    rm -rf "$profile"
    # Pop-outs keeps only the strip of bubbles at the top.
    crop=(); [[ $story == popouts ]] && crop=(-vf crop=1640:320:0:0)
    ffmpeg -nostdin -hide_banner -loglevel error -y -framerate 60 -i "$output/$story/$story-frames/f%05d.png" ${crop[@]+"${crop[@]}"} -an -c:v libx264 -threads 2 -preset medium -crf 20 -pix_fmt yuv420p \
      -colorspace bt709 -color_primaries bt709 -color_trc bt709 -movflags +faststart "$output/site/$story.mp4"
    ffmpeg -nostdin -hide_banner -loglevel error -y -i "$output/$story/$story-poster.png" ${crop[@]+"${crop[@]}"} "$output/site/$story-poster.png"
    rm -rf "$output/$story"
  done
  # The Tools images and the converter reel, drawn off screen on the page colour.
  profile=$(mktemp -d "$work/profile.XXXXXX")
  MACSPACES_DEMO_FIXTURE_ROOT="$profile" TMPDIR="$profile/" TZ=America/Chicago NSUnbufferedIO=YES MACSPACES_WEBSITE_DEMO=1 MACSPACES_DEMO_KIND=tools \
  MACSPACES_DEMO_LOCAL=1 MACSPACES_DEMO_SEQUENCE="$root/Demos/music-sequence.json" MACSPACES_DEMO_TRACKS="$work/assets/tracks.json" MACSPACES_DEMO_OUTPUT="$output/tools" \
    "$work/build/Build/Products/Debug/MacSpaces.app/Contents/MacOS/MacSpaces" >> "$output/capture.log" 2>&1
  ffmpeg -nostdin -hide_banner -loglevel error -y -framerate 60 -i "$output/tools/clip-converter-reel/f%05d.png" -vf "crop=in_h:in_h,scale=900:900" -an -c:v libx264 -threads 2 -preset medium -crf 20 -pix_fmt yuv420p \
    -colorspace bt709 -color_primaries bt709 -color_trc bt709 -movflags +faststart "$output/site/converter.mp4"
  ffmpeg -nostdin -hide_banner -loglevel error -y -i "$output/tools/clip-converter-reel/f00030.png" -vf "crop=in_h:in_h,scale=900:900" "$output/site/converter-poster.png"
  cp "$output/tools/clipboard.png" "$output/tools/basket.png" "$output/site/"
  cp "$output"/tools/check-*.png "$output/"
fi
# Publication copies only the approved filenames; the five-song proof sheet stays in this output.
[[ $mode == test ]] || PORTFOLIO="${PORTFOLIO:-$root/../PORTFOLIO}" "$root/Scripts/publish-demos.sh" --from "$output"
rm -rf "$raw"
echo "Demos and stills are ready in $output. Local website/README copies are updated; nothing was committed or published."
