#!/bin/bash
# Run before pushing a branch or dispatching CI or Feature QA: one incremental Debug arm64
# compile of the harness (as CI and Feature QA build it), then the check scripts. It catches
# compile errors here instead of on a GitHub runner.
#
#   Scripts/preflight.sh            build, then every check script
#   Scripts/preflight.sh --build    build only
#   Scripts/preflight.sh --clean    delete this checkout's preflight build and exit
#
# Build output goes to ~/Library/Caches/MacSpaces-preflight (outside iCloud), one folder per
# checkout so the next run is incremental. It refuses while this Mac is short of memory or
# another xcodebuild runs, and limits the compiler to four jobs to stay under about 4 GB.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD

cache="$HOME/Library/Caches/MacSpaces-preflight"
derived="$cache/$(basename "$root")-$(printf '%s' "$root" | shasum | cut -c1-8)"

case "${1:-}" in
  --clean) rm -rf "$derived"; echo "Removed $derived"; exit 0 ;;
  --build|"") ;;
  *) echo "usage: Scripts/preflight.sh [--build | --clean]" >&2; exit 2 ;;
esac

# Shared Mac: free memory at least 40%, swap at most 6 GB, one build at a time.
if command -v mac-status > /dev/null; then
  line=$(mac-status 2>/dev/null | grep -m1 '^free:' || true)  # "free: 69%, swap 1269.94M of 2048.00M"
else
  line="free: $(memory_pressure | tail -1 | grep -oE '[0-9]+%'), swap $(sysctl -n vm.swapusage | awk '{print $6}')"
fi
free=$(sed -nE 's/^free: ([0-9]+)%.*/\1/p' <<< "$line")
swap_mb=$(sed -nE 's/.*swap ([0-9.]+)([MG]).*/\1 \2/p' <<< "$line" | awk '{print ($2 == "G") ? $1 * 1024 : $1}')
if [ -z "$free" ] || [ -z "$swap_mb" ]; then
  echo "preflight: couldn't read free memory and swap ('$line')" >&2; exit 1
fi
if [ "$free" -lt 40 ] || awk "BEGIN {exit !($swap_mb > 6144)}"; then
  echo "preflight: not now: $line (needs free memory of at least 40% and swap at most 6 GB). Try again later." >&2
  exit 75
fi
if pgrep -x xcodebuild > /dev/null; then
  echo "preflight: another xcodebuild is running (see mac-status); one build at a time. Try again later." >&2
  exit 75
fi

mkdir -p "$derived"
start=$SECONDS

# xcodegen skips regenerating when the spec and file list are unchanged.
xcodegen generate --use-cache --cache-path "$derived/xcodegen-cache" --quiet

build() { # bundle identifier
  xcodebuild -project MacSpaces.xcodeproj -scheme MacSpaces -configuration Debug \
    -derivedDataPath "$derived" -clonedSourcePackagesDirPath "$cache/SourcePackages" \
    -skipPackagePluginValidation -jobs 4 -quiet \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES PRODUCT_BUNDLE_IDENTIFIER="$1" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
    build > "$derived/build.log" 2>&1
}
failed=()
report() { # what failed
  errors=$(grep -E ': error: ' "$derived/build.log" | sed -e "s|$root/||" -e "s|${root#/private}/||" | awk '!seen[$0]++' || true)
  echo "preflight: $1 failed to build ($(grep -c . <<< "$errors") errors); full log: $derived/build.log" >&2
  if [ -n "$errors" ]; then head -20 <<< "$errors" >&2; else tail -20 "$derived/build.log" >&2; fi
  failed+=("$1 build")
}
# FeatureQA compiles everything; WebsiteDemo only relinks and re-signs the same objects.
if build dev.opensource.MacSpaces.FeatureQA; then
  build dev.opensource.MacSpaces.WebsiteDemo || report WebsiteDemo
else
  report FeatureQA
fi
[ ${#failed[@]} = 0 ] && echo "preflight: harness builds ($((SECONDS - start)) s)"

[ "${1:-}" = --build ] && exit $(( ${#failed[@]} > 0 ))

# Every check script CI runs, one after another, even after a failed build. While the
# screen is locked, check-notes can't reopen the protected file it writes, so it's left to CI.
locked=$(ioreg -n Root -d1 -k IOConsoleUsers 2> /dev/null | grep -c '"CGSSessionScreenIsLocked"=Yes' || true)
for check in Scripts/check-*.sh; do
  if [ "$locked" != 0 ] && [ "$check" = Scripts/check-notes.sh ]; then
    echo "preflight: skipped check-notes (screen locked; CI runs it)"
    continue
  fi
  if ! out=$("$check" 2>&1); then
    failed+=("$(basename "$check" .sh)")
    echo "preflight: $check failed:" >&2
    tail -15 <<< "$out" >&2
  fi
done
if [ ${#failed[@]} -gt 0 ]; then
  echo "preflight: failed: ${failed[*]}" >&2
  exit 1
fi
echo "preflight: passed in $((SECONDS - start)) s"
