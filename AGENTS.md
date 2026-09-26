# MacSpaces engineering guide

MacSpaces 1.1 is a native macOS menu-bar app focused on the Nook. A panel opens
from the physical camera notch, or a synthetic notch on other displays. It has
widget profiles, a file Tray, compact live activities, optional Mirror, and lyrics.

## Architecture

- `Sources/App`: app entry, menu, Nook activation, service demand and updates.
  `ModuleCoordinator` creates only `NotchManager`.
- `Sources/Modules/Notch/Core`: display geometry, per-display windows, hover,
  collapse/expand state and sizing.
- `Sources/Modules/Notch/UI`: panel shape, header, live activities and transitions.
- `Sources/Modules/Notch/Features/Widgets`: dashboard and reusable widget views.
  `NookWidgetKind` is the user-facing widget catalog. Its cases drive the library,
  persistence and view factory. New cases must have titles, symbols and sizing.
- `Sources/DesignSystem`: shared appearance and palette persistence. Only the
  modern widget style is selectable; old style identifiers decode to it.
  `Design` owns the motion tokens (open/close/hover springs, `nookDepth`
  transitions) and optional trackpad `Haptics`; all of them honor Reduce Motion.
- `Sources/Settings`: General (enable, startup, behavior, displays, software
  updates), Widgets (profiles, visual editor, lyrics, relevant access),
  Appearance (palette, size, motion) and Activities. There is no About page;
  the installed version appears with software updates in General. Permissions stay with enabled widgets.
  Settings remember the current destination; Nook shortcuts open the relevant page.
- `Sources/Services`: media, weather, calendar, clipboard, timers and related tools.
- `Sources/Debug`: isolated demo rendering and regression assertions.

Nook columns grow proportionally to fill available width. Adjacent compact
widgets can stack. Oversized profiles retain useful tile widths and scroll.
Panel heights fill the configured size. Header controls stay outside the camera
cutout; narrow displays place the header below it. Empty profiles keep Add Widget.

Service demand follows enabled Nook widgets. Clipboard history is memory-only
and excludes concealed/transient pasteboard types. Weather starts only when its
widget is enabled; hover details keep the Nook open. Weather uses Open-Meteo and
an IP location fallback. Lyrics use their provider, and updates use GitHub.
Only the Battery widget starts Bluetooth monitoring. There are no Bluetooth
connection or device-battery live activities; power feedback precedes routine
system-control feedback, and the host window tracks live activity size.
Bluetooth uses paired-device reads plus the macOS connected-device report when
IOBluetooth omits accessories. Battery reads are cached for 30 seconds; connection
fallback refreshes every four seconds. Unknown values stay unknown, and earbud
and case levels remain separate. Power uses the internal battery's capacity ratio
and charging flag, not the presence of external power.
Camera access belongs only to the optional Mirror. Never request permissions for
unused features or use real camera/clipboard content in promotional captures.

## Build and release

Swift 5.9; macOS 13 deployment target; Xcode and XcodeGen. `project.yml` is the
canonical project definition. The generated Xcode project is ignored.

Bundle: `dev.opensource.MacSpaces`. Team: `28LJG7MXT3`. Versions are in project.yml.
Keep the bundle identifier stable to preserve settings and update verification.

`make` builds locally. `make release` runs Scripts/package-release.sh: universal
arm64/x86_64 Release build, Developer ID signature with hardened runtime, app
notarization, stapling, DMG creation, DMG notarization and stapling, then mounted
app signature, architecture and Gatekeeper verification. Keychain profile:
`MacSpaces`. Never commit credentials, generated projects or release artifacts.
### Release policy

The owner moved from the fixed 1.0.0 snapshot to versioned releases with 1.1.

- `main` is normal history: add commits; do not rewrite or force-push it. The
  `v1.0.0` tag and release stay as they are. Commit titles for a release are
  `MacSpaces X.Y`.
- Each public version gets one tag, `vX.Y`, at its commit on `main`, and one
  GitHub Release, `MacSpaces X.Y`, with `MacSpaces.dmg`. A replacement installer
  for the same version updates that release instead of creating another.
- `CFBundleShortVersionString` is the public version. Increment the internal
  integer `CFBundleVersion` for every published installer; it must exceed every
  published release's build so existing installs detect the update.
- Run `Scripts/check-release-policy.sh`, the updater regression checks and the
  build. Check CI on the exact release commit, push the `vX.Y` tag there, then
  run `make release` and `Scripts/publish-release.sh`, which creates or updates
  that version's release.
- `RELEASE_NOTES.md` describes the current version and names it in bold. The
  publisher adds one hidden `macspaces-build` marker for update detection.

The updater reads releases/latest, takes the public version from its tag,
compares internal build numbers, and checks the downloaded app's version, build,
bundle identifier and signing-team identity. 1.0.0 builds only accepted a
`v1.0.0` tag, so they cannot update to 1.1 automatically; users install 1.1 once
from the release page.

CI builds Release on macos-14. A passing local build is insufficient: check the
GitHub build on the commit being released. Use explicit captures in nested actor
closures for compatibility with the CI compiler.

## Demo and regression checks

Build Debug with PRODUCT_BUNDLE_IDENTIFIER=dev.opensource.MacSpaces.WebsiteDemo.
Launch with MACSPACES_WEBSITE_DEMO=1 and optionally MACSPACES_DEMO_OUTPUT.
The helper requires the separate bundle identifier, uses synthetic data, and
never reads real camera or clipboard content. Artwork paths are explicit in
WebsiteDemoCapture. Only safe, populated native Nook views are exported.

DeviceRegressionChecks verifies power semantics and component battery parsing.
MACSPACES_DEVICE_AUDIT=1 performs
a read-only local-device check; it logs counts only, never names or addresses.
InteractionRegressionChecks verifies proportional fill, stacked sizing, new
widget persistence, the Nook-only sidebar and legacy style migration. Native
captures check empty/small profiles and physical camera clearance. Inspect
settings and the Gold, Midnight and Everforest scenes visually before shipping.
