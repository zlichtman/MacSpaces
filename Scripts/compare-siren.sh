#!/bin/bash
# MacSpaces' voice engine side by side with Siren's, on real recordings, on the owner's Mac only.
# Not a check: preflight, CI and Feature QA never run it (it isn't a check-*.sh).
#
#   Scripts/compare-siren.sh <recordings folder> [--lines <file>] [--output <folder>] [--engine <id>]
#                            [--siren-check <path to siren-check>] [--siren-takes <folder>] [--keep-build]
#                            [--hub <models folder>]... [--truth <folder>]
#
# For each recording it sorts the recording, keeps the most heard person's clip as the reference,
# reads every line (one per line of --lines, else three of its own) Fast and with Best Quality on
# the same seed, and scores each WAV's likeness to the reference with the fingerprint model that
# sorts and joins voices (cosine, higher is more like them). With --siren-check it also runs Siren's
# command, `siren-check <reference.wav> <transcript> <text> <out.wav> [--small]`, on the same
# reference and lines; with --siren-takes it scores takes exported from the Siren app, named
# <recording name>-<line number>.wav. Output: per recording reference.wav, reference.txt,
# macspaces-fast-N.wav, macspaces-best-N.wav and any siren-*.wav, plus report.txt and report.json.
#
# Models come from MacSpaces' own downloads (Finding voices and an engine, in Settings, Tsukumo,
# Voice), cloned into the temporary build folder (APFS clones take no space) and never changed.
# --hub uses that models folder instead (a Hugging Face cache laid out as Voices/Models is), read
# as it is; given more than once, every recording is compared with each in turn, for example one
# with Music removal and one without. --truth is a folder of the same recordings, same names,
# without what was mixed into them: each reference is also scored against its clean recording.
# --engine is a VoiceModel id: standard, standard-small or expressive (else the one this Mac fits).
# It builds the optimised Debug harness (one build, about 3 GB, a few minutes), then runs it:
# each line costs a few seconds Fast and up to three times that with Best Quality, and the helper
# peaks near 4.2 GB with Standard (its weights are 3.1 GB); it's stopped past 4.5 GB.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
usage() { sed -n '5,7p' "$0" | sed 's/^# //' >&2; exit 2; }
input="" lines="" output="" engine="" siren="" siren_takes="" keep_build=0 hubs="" truth=""
while (($#)); do
  case "$1" in
    --lines) lines=${2:?}; shift ;;
    --output) output=${2:?}; shift ;;
    --engine) engine=${2:?}; shift ;;
    --siren-check) siren=${2:?}; shift ;;
    --siren-takes) siren_takes=${2:?}; shift ;;
    --keep-build) keep_build=1 ;;
    --hub) [[ -d "${2:?}" ]] || { echo "No folder at $2" >&2; exit 2; }; hubs+="${hubs:+:}$(cd "$2" && pwd)"; shift ;;
    --truth) truth=${2:?}; shift ;;
    --help|-h) usage ;;
    -*) usage ;;
    *) [[ -z "$input" ]] || usage; input=$1 ;;
  esac
  shift
done
[[ -n "$input" && -d "$input" ]] || usage
absolute() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd)" "$(basename "$1")"); }
input=$(absolute "$input")
[[ -z "$lines" ]] || { [[ -f "$lines" ]] || { echo "No lines file at $lines" >&2; exit 2; }; lines=$(absolute "$lines"); }
[[ -z "$siren" ]] || { [[ -x "$siren" ]] || { echo "siren-check isn't an executable at $siren" >&2; exit 2; }; siren=$(absolute "$siren"); }
[[ -z "$siren_takes" ]] || { [[ -d "$siren_takes" ]] || { echo "No folder at $siren_takes" >&2; exit 2; }; siren_takes=$(absolute "$siren_takes"); }
[[ -z "$truth" ]] || { [[ -d "$truth" ]] || { echo "No folder at $truth" >&2; exit 2; }; truth=$(absolute "$truth"); }
models="$HOME/Library/Application Support/MacSpaces/Voices/Models"
[[ -n "$hubs" || -d "$models" ]] || { echo "No voice models: download Finding voices and an engine in MacSpaces, Settings, Tsukumo, Voice." >&2; exit 1; }
for tool in xcodegen xcodebuild; do
  command -v "$tool" >/dev/null || { echo "Missing $tool (brew install xcodegen)." >&2; exit 1; }
done

# One heavy job at a time on this Mac.
line=$(mac-status 2>/dev/null | sed -n '/^free:/p' || true)
free=$(sed -nE 's/^free: ([0-9]+)%.*/\1/p' <<< "$line")
swap=$(sed -nE 's/.*swap ([0-9.]+)([MG]).*/\1 \2/p' <<< "$line" | awk '{print ($2 == "G") ? $1 * 1024 : $1}')
if [[ -z "$free" || -z "$swap" ]]; then echo "Can't read mac-status; stopping before building." >&2; exit 75; fi
if [[ "$free" -lt 40 ]] || awk "BEGIN {exit !($swap > 6144)}" || pgrep -x xcodebuild >/dev/null; then
  echo "Wait for memory or the other build to finish ($line)." >&2; exit 75
fi

[[ -n "$output" ]] || output="${TMPDIR:-/tmp}/MacSpaces-compare-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$output"
output=$(absolute "$output")
work=$(mktemp -d "${TMPDIR:-/tmp}/macspaces-compare.XXXXXX")
app_pid=""
cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then kill "$app_pid" 2>/dev/null || true; fi
  # Only this build's voice helper; MacSpaces' own keeps running.
  pkill -f "^$work/build/" 2>/dev/null || true
  if ((keep_build)); then echo "Build kept in $work" >&2; else rm -rf "$work"; fi
  rm -rf "${TMPDIR:-/tmp}/MacSpacesFixtures/dev.opensource.MacSpaces.FeatureQA"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# The downloaded models, cloned: the harness reads them and never touches the originals.
if [[ -z "$hubs" ]]; then cp -cR "$models" "$work/Models"; hubs="$work/Models"; fi

# The harness, optimised (MLX in an unoptimised build is several times slower).
ln -s "$root/Sources" "$work/Sources"
ln -s "$root/Helpers" "$work/Helpers"
ln -s "$root/Packages" "$work/Packages"
xcodegen generate --spec "$root/project.yml" --project "$work" --quiet
echo "Building the harness (log: $output/build.log)"
xcodebuild -project "$work/MacSpaces.xcodeproj" -scheme MacSpaces -configuration Debug -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$work/build" -clonedSourcePackagesDirPath "$work/spm" \
  -skipPackagePluginValidation -jobs 4 -quiet ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  PRODUCT_BUNDLE_IDENTIFIER=dev.opensource.MacSpaces.FeatureQA CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule GCC_OPTIMIZATION_LEVEL=s \
  build > "$output/build.log" 2>&1 || { tail -30 "$output/build.log" >&2; exit 1; }

echo "Comparing (report: $output/report.txt)"
MACSPACES_FEATURE_QA="$output" MACSPACES_QA_SCOPE=voices-compare MACSPACES_COMPARE_INPUT="$input" \
  MACSPACES_COMPARE_HUB="$hubs" MACSPACES_COMPARE_TRUTH="$truth" MACSPACES_COMPARE_LINES="$lines" MACSPACES_COMPARE_ENGINE="$engine" \
  MACSPACES_COMPARE_SIREN="$siren" MACSPACES_COMPARE_SIREN_TAKES="$siren_takes" \
  "$work/build/Build/Products/Debug/MacSpaces.app/Contents/MacOS/MacSpaces" > "$output/harness.log" 2>&1 &
app_pid=$!
wait "$app_pid" || true
app_pid=""
cat "$output/report.txt" 2>/dev/null || { echo "No report; see $output/harness.log" >&2; exit 1; }
echo "WAVs and report.json are in $output"
