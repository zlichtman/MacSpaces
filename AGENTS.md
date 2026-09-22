# MacSpaces engineering guide

MacSpaces 1.0.0 is a native macOS menu-bar app focused on the Nook. A panel opens
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
- `Sources/Settings`: General (enable, startup, behavior, displays), Widgets
  (profiles, visual editor, lyrics, relevant access), Appearance (palette, size,
  motion), Activities, and About & Updates. Permissions stay with enabled widgets.
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
Battery widgets also keep Bluetooth monitoring active. Connection and battery
feedback precede routine system-control feedback. The host window tracks live
activity size, including long accessory names on displays without a notch.
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
### Permanent release policy

The owner requires **one commit and one release, always named 1.0.0**. This is an
explicit repository convention, including future work:

- Keep `main` as one root commit. Amend that commit; do not append commits, merge
  PRs, or leave additional public branches. Keep the commit title `MacSpaces 1.0.0`.
- Keep exactly one tag, `v1.0.0`, and one GitHub Release, `MacSpaces 1.0.0`.
  Replace that release's `MacSpaces.dmg`; never create a second release or tag.
- Keep `CFBundleShortVersionString` at `1.0.0`. Increment the internal integer
  `CFBundleVersion` for each replacement so existing installs can detect updates.
- Before replacing history or an installer, save a local recovery bundle and a
  copy of the previous release outside the repository. Never publish backup refs.
- Record the current remote main/tag SHAs; push the amended main and moved tag
  with explicit `--force-with-lease=<ref>:<expected-sha>` checks. If a lease fails,
  inspect the new remote work and preserve it before proceeding.
- Run `Scripts/check-release-policy.sh`, the updater regression checks and the
  build. Check CI on the exact replacement commit, then `make release` and
  `Scripts/publish-release.sh`. The publisher only updates the existing release.
- `RELEASE_NOTES.md` describes the current app, not a list of past versions. The
  publisher adds one hidden `macspaces-build` marker for update detection.

The updater reads releases/latest, compares internal build numbers, and checks
the downloaded app's version, build, bundle identifier and signing-team identity.
Do not remove build metadata: the public version intentionally remains fixed.

CI builds Release on macos-14. A passing local build is insufficient: check the
GitHub build on the commit being released. Use explicit captures in nested actor
closures for compatibility with the CI compiler.

## Demo and regression checks

Build Debug with PRODUCT_BUNDLE_IDENTIFIER=dev.opensource.MacSpaces.WebsiteDemo.
Launch with MACSPACES_WEBSITE_DEMO=1 and optionally MACSPACES_DEMO_OUTPUT.
The helper requires the separate bundle identifier, uses synthetic data, and
never reads real camera or clipboard content. Artwork paths are explicit in
WebsiteDemoCapture. Only safe, populated native Nook views are exported.

DeviceRegressionChecks verifies power semantics, component battery parsing,
gradual battery changes and connection events. MACSPACES_DEVICE_AUDIT=1 performs
a read-only local-device check; it logs counts only, never names or addresses.
InteractionRegressionChecks verifies proportional fill, stacked sizing, new
widget persistence, the Nook-only sidebar and legacy style migration. Native
captures check empty/small profiles and physical camera clearance. Inspect
settings and the Gold, Midnight and Everforest scenes visually before shipping.
