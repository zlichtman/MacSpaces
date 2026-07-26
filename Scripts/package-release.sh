#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Sources/Resources/Info.plist")"
RELEASES_DIR="$PROJECT_ROOT/Releases"
STAGING_ROOT="$(mktemp -d "${TMPDIR%/}/macspaces-package.XXXXXX")"
DERIVED_DATA="$STAGING_ROOT/DerivedData"
PROJECT_BUILD_ROOT="$STAGING_ROOT/Project"
APP_SOURCE="$DERIVED_DATA/Build/Products/Release/MacSpaces.app"
APP_STAGED="$STAGING_ROOT/MacSpaces.app"
DMG_ROOT="$STAGING_ROOT/dmg"
DMG_STAGED="$STAGING_ROOT/MacSpaces.dmg"
DMG_PATH="$RELEASES_DIR/MacSpaces.dmg"
VERIFY_MOUNT="$STAGING_ROOT/verify-mount"
ENTITLEMENTS_PATH="$PROJECT_ROOT/Sources/Resources/MacSpaces.entitlements"
NOTARIZE="${MACSPACES_NOTARIZE:-0}"
NOTARY_PROFILE="${MACSPACES_NOTARY_PROFILE:-MacSpaces}"

cleanup() {
  hdiutil detach "$VERIFY_MOUNT" >/dev/null 2>&1 || true
  if [[ "${MACSPACES_KEEP_STAGING:-0}" == "1" ]]; then
    echo "Preserved staging directory: $STAGING_ROOT"
  else
    rm -rf "$STAGING_ROOT"
  fi
}
trap cleanup EXIT

if [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
  XCODEBUILD=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
elif [[ -x /Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild ]]; then
  XCODEBUILD=/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild
else
  XCODEBUILD="$(command -v xcodebuild)"
fi

mkdir -p "$RELEASES_DIR" "$PROJECT_BUILD_ROOT"
ln -s "$PROJECT_ROOT/Sources" "$PROJECT_BUILD_ROOT/Sources"

cd "$PROJECT_ROOT"
xcodegen generate \
  --spec "$PROJECT_ROOT/project.yml" \
  --project "$PROJECT_BUILD_ROOT" \
  --project-root "$PROJECT_ROOT" \
  --cache-path "$STAGING_ROOT/xcodegen-cache"

"$XCODEBUILD" \
  -quiet \
  -project "$PROJECT_BUILD_ROOT/MacSpaces.xcodeproj" \
  -scheme MacSpaces \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

ditto "$APP_SOURCE" "$APP_STAGED"

SIGNING_IDENTITY="${MACSPACES_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  SIGNING_IDENTITY="$(printf '%s\n' "$AVAILABLE_IDENTITIES" | awk -F'"' '/Developer ID Application:/ { print $2; exit }')"
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(printf '%s\n' "$AVAILABLE_IDENTITIES" | awk -F'"' '/Apple Development:/ { print $2; exit }')"
  fi
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  SIGNING_ARGS=(
    --force
    --options runtime
    --entitlements "$ENTITLEMENTS_PATH"
    --sign "$SIGNING_IDENTITY"
  )
  if [[ "$SIGNING_IDENTITY" == Developer\ ID\ Application:* ]]; then
    SIGNING_ARGS+=(--timestamp)
    SIGNING_KIND="Developer ID Application"
  else
    SIGNING_ARGS+=(--timestamp=none)
    SIGNING_KIND="Development"
  fi
  codesign "${SIGNING_ARGS[@]}" "$APP_STAGED"
  SIGNING_DESCRIPTION="$SIGNING_IDENTITY"
else
  codesign \
    --force \
    --options runtime \
    --entitlements "$ENTITLEMENTS_PATH" \
    --sign - \
    --timestamp=none \
    "$APP_STAGED"
  SIGNING_DESCRIPTION="Ad-hoc (no keychain identity found)"
  SIGNING_KIND="Ad-hoc"
fi

codesign --verify --deep --strict --verbose=2 "$APP_STAGED"

package_dmg() {
  rm -rf "$DMG_ROOT"
  mkdir -p "$DMG_ROOT"
  ditto "$APP_STAGED" "$DMG_ROOT/MacSpaces.app"
  codesign --verify --deep --strict --verbose=2 "$DMG_ROOT/MacSpaces.app"
  ln -s /Applications "$DMG_ROOT/Applications"
  rm -f "$DMG_STAGED"
  hdiutil create \
    -volname "MacSpaces $VERSION" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_STAGED"
}

NOTARIZATION_STATUS="Not submitted"
if [[ "$NOTARIZE" == "1" ]]; then
  if [[ "$SIGNING_KIND" != "Developer ID Application" ]]; then
    echo "Notarization requires a Developer ID Application identity." >&2
    exit 1
  fi

  NOTARY_ZIP="$STAGING_ROOT/MacSpaces-notary.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_STAGED" "$NOTARY_ZIP"
  xcrun notarytool submit \
    "$NOTARY_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --timeout 30m
  xcrun stapler staple "$APP_STAGED"
  xcrun stapler validate "$APP_STAGED"
  NOTARIZATION_STATUS="Accepted and stapled"
fi

package_dmg

if [[ -n "$SIGNING_IDENTITY" ]]; then
  DMG_SIGNING_ARGS=(--force --sign "$SIGNING_IDENTITY")
  if [[ "$SIGNING_IDENTITY" == Developer\ ID\ Application:* ]]; then
    DMG_SIGNING_ARGS+=(--timestamp)
  else
    DMG_SIGNING_ARGS+=(--timestamp=none)
  fi
  codesign "${DMG_SIGNING_ARGS[@]}" "$DMG_STAGED"
else
  codesign --force --sign - --timestamp=none "$DMG_STAGED"
fi
codesign --verify --strict --verbose=2 "$DMG_STAGED"

# Verify the exact signed payload before publishing its disk image.
VERIFY_ARCHS="$(lipo -archs "$APP_STAGED/Contents/MacOS/MacSpaces")"
if [[ "$VERIFY_ARCHS" != *arm64* || "$VERIFY_ARCHS" != *x86_64* ]]; then
  echo "Packaged executable is not universal: $VERIFY_ARCHS" >&2
  exit 1
fi

if [[ "$NOTARIZE" == "1" ]]; then
  xcrun notarytool submit \
    "$DMG_STAGED" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    --timeout 30m
  xcrun stapler staple "$DMG_STAGED"
  xcrun stapler validate "$DMG_STAGED"
fi

# A release is publishable only when the app survives an actual image
# round-trip with its bundle signature and both architectures intact.
mkdir -p "$VERIFY_MOUNT"
hdiutil attach \
  -nobrowse \
  -readonly \
  -mountpoint "$VERIFY_MOUNT" \
  "$DMG_STAGED" \
  >/dev/null
codesign --verify --deep --strict --verbose=2 "$VERIFY_MOUNT/MacSpaces.app"
MOUNTED_ARCHS="$(lipo -archs "$VERIFY_MOUNT/MacSpaces.app/Contents/MacOS/MacSpaces")"
if [[ "$MOUNTED_ARCHS" != *arm64* || "$MOUNTED_ARCHS" != *x86_64* ]]; then
  echo "Mounted executable is not universal: $MOUNTED_ARCHS" >&2
  exit 1
fi
hdiutil detach "$VERIFY_MOUNT" >/dev/null

# Publish only after build, signing, architecture, and optional notarization
# checks have all completed. Releases intentionally contains one user-facing
# artifact so Finder never presents stale or ambiguous downloads.
rm -rf "$RELEASES_DIR/MacSpaces.app"
rm -f \
  "$RELEASES_DIR/.DS_Store" \
  "$RELEASES_DIR/BUILD-INFO.txt" \
  "$RELEASES_DIR/SHA256SUMS.txt"
mv -f "$DMG_STAGED" "$DMG_PATH"

echo "Created:"
echo "  $DMG_PATH"
echo "Signed with: $SIGNING_DESCRIPTION"
echo "Notarization: $NOTARIZATION_STATUS"
