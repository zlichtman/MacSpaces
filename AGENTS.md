# MacSpaces engineering guide

MacSpaces is a native macOS menu-bar app focused on the Nook. A panel opens
from the physical camera notch, or a synthetic notch on other displays. It has
widget profiles, a file Tray, compact live activities, optional Mirror, and lyrics.

## Current development state

The working tree is **2.36** (build 36), macOS 26+ and Apple Silicon, published
as a GitHub pre-release. The stable release is **1.14** (macOS 13+), the parent
commit. See Documentation/BUILD-STATUS.md and the 95-entry feature audit before
claiming any 2.x capability is complete. MacSpacesDevelopmentBuild marks 2.x as a
pre-release build: it updates from the pre-release channel (see Release policy)
and cannot be published as a stable release. Keep that flag, and keep 2.x a
pre-release, so 1.x installs are never offered it.

## Architecture

- `Sources/Core`: pure feature/action catalogs and dependency-aware service lifecycle.
  Run `Scripts/check-core.sh` for lifecycle ordering, rollback and action safety.
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
  Appearance (theme, accessibility), Permissions, and Activities. There is no About page;
  the installed version appears with software updates in General. Permissions are reviewed in the dedicated Permissions page; opening it does not request access.
  Settings remember the current destination; Nook shortcuts open the relevant page.
- `Sources/Services`: media, weather, calendar, clipboard, timers and related tools.
- `Sources/Debug`: isolated demo rendering and regression assertions.

Nook columns grow proportionally to fill available width. Adjacent compact
widgets can stack. Oversized profiles retain useful tile widths and scroll.
The dock's app pages are user-configurable (`NookSettings.dockApps`); Home and
Settings are always present, and file drops still open Tray when it is hidden.
Panel sizing follows the active content and display, with fixed visual proportions. Legacy manual sizing preferences are retained for compatibility but do not control geometry. A detached navigation dock sits below the panel. Content starts below the physical camera cutout; the shared hover region includes the gap to the dock. Empty profiles keep Add Widget.
File drags open Tray only after pausing in a small zone around the closed notch
(General → "Open Tray when dragging files to the notch" turns this off).

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

Swift 5.9; macOS 26 deployment target; Xcode and XcodeGen. `project.yml` is the
canonical project definition. The generated Xcode project is ignored.

Bundle: `dev.opensource.MacSpaces`. Team: `28LJG7MXT3`. Versions are in project.yml.
Keep the bundle identifier stable to preserve settings and update verification.

`make` builds locally. `make release` runs Scripts/package-release.sh: arm64 Release build, Developer ID signature with hardened runtime, app
notarization, stapling, DMG creation, DMG notarization and stapling, then mounted
app signature, architecture and Gatekeeper verification. Keychain profile:
`MacSpaces`. Never commit credentials, generated projects or release artifacts.

### Release policy

`main` holds one commit per major version: the root `MacSpaces 1.14` and
`MacSpaces 2.36` on top of it. Each has its own README. Public releases use
versioned tags and installers.

- Updating a major version replaces its commit (1.x stays the root; 2.x is
  rebuilt on top). Do not publish recovery bundles, backup branches, or spare
  app copies. Push with an explicit force-with-lease for the previously
  inspected remote SHA. Existing release tags and assets stay unchanged unless
  a release update is requested. Commit titles are `MacSpaces X.Y`.
- Each public version gets one tag, `vX.Y`, at its commit on `main`, and one
  GitHub Release, `MacSpaces X.Y`, with `MacSpaces.dmg`. A replacement installer
  for the same version updates that release instead of creating another.
- `CFBundleShortVersionString` is the public version. From 2.x it is
  `major.build` (2.32, 2.33, …) so the build is part of the name; 1.0.0 predates
  this. Increment the integer `CFBundleVersion` for every published installer
  and keep the public version's second number equal to it; it must exceed every
  published release's build so existing installs detect the update.
- Run `Scripts/check-release-policy.sh`, the updater regression checks and the
  build. Check CI on the exact release commit, push the `vX.Y` tag there, then
  run `make release` and `Scripts/publish-release.sh`, which creates or updates
  that version's release.
- `RELEASE_NOTES.md` describes the current version and names it in bold. The
  publisher adds one hidden `macspaces-build` marker for update detection.

Stable (1.x) installs read releases/latest. Pre-release (2.x) installs read the
release list and take the newest non-draft release with their own major version
(`ReleaseRevision.newest`), so they never receive 1.x or a future 3.x; they
download automatically by default. Both take the public version from the tag,
compare internal build numbers, check hourly (at most every six hours) while
running, and verify the downloaded app's version, build, bundle identifier and
signing-team identity before asking to relaunch. QA and demo bundles never update. Replacement installers use
increasing internal builds. 1.14 is the latest (stable) release. 2.x releases are
GitHub pre-releases, which releases/latest never returns, so 1.x installs on
older macOS or Intel Macs are never offered a build they cannot run.
Scripts/publish-release.sh publishes stable 1.x releases only; 2.x pre-releases
are published by hand with the same signature, notarization and build-marker checks.
Homebrew: `zlichtman/tap/macspaces` installs 1.x, `zlichtman/tap/macspaces@beta` installs 2.x.

CI builds Release on macos-26 (arm64). A passing local build is insufficient: check the
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

Appearance uses ThemeFamily for paired light/dark palettes and AppearanceMode for System/Light/Dark. Exactly five app themes come first: MacSpaces, PowderMeet, Heartable, KemoSabe and Tsukumo. A second row of five follows: Noir, Rosé Pine, Kanagawa, Ayu and Custom (user-chosen background and accent, stored as CustomThemeColors; text is pure white or black for contrast). Other palettes appear once in a separate collection. Preview images contain no appearance or variant labels. Settings and the Nook menu use the same catalog. ThemePreset remains a compatibility catalog: do not remove saved IDs or overwrite custom colors. App icons are independent of appearance. Run Scripts/check-appearance.sh for migration and contrast checks.
