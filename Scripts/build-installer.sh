#!/bin/bash
# Build a branded Finder disk image from an already signed (and, for release,
# already stapled) app. Signing/notarization of the DMG stays in package-release.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# != 3 ]]; then
  echo "Usage: $0 /path/MacSpaces.app /path/output.dmg volume-name" >&2
  exit 2
fi
app="$1"
output="$2"
volume="$3"
[[ "$app" = /* && "$output" = /* ]] || { echo 'Use absolute app and output paths.' >&2; exit 2; }
[[ -d "$app/Contents" && ! -e "$output" ]] || { echo 'App is missing or output already exists.' >&2; exit 2; }
codesign --verify --deep --strict "$app"
temp_root="${TMPDIR:-/tmp}"
stage=$(mktemp -d "${temp_root%/}/macspaces-installer.XXXXXX")
complete=0
cleanup() {
  rm -rf "$stage"
  if [[ "$complete" != 1 ]]; then rm -f "$output"; fi
}
trap cleanup EXIT
python="${MACSPACES_DMG_PYTHON:-}"
if [[ -z "$python" ]]; then
  python3 -m venv "$stage/tools"
  python="$stage/tools/bin/python"
  "$python" -m pip install --disable-pip-version-check -r "$root/Scripts/installer/requirements.txt"
fi
swift "$root/Scripts/installer/render-background.swift" "$stage/background.tiff" \
  "$root/Sources/Resources/MacSpacesIcon-master.png"
"$python" -m dmgbuild -s "$root/Scripts/installer/layout.py" \
  -D "app=$app" -D "background=$stage/background.tiff" "$volume" "$output"
hdiutil verify "$output"
complete=1
