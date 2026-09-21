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
- `Sources/Settings`: Nook, Theme, Permissions and About. The Nook page starts with
  enable and a visual widget editor. Theme stays above Permissions in the sidebar.
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
Publish the verified `MacSpaces.dmg` on a versioned GitHub Release; the updater
reads releases/latest and checks bundle and signing-team identity.

CI builds Release on macos-14. A passing local build is insufficient: check the
GitHub build on the commit being released. Use explicit captures in nested actor
closures for compatibility with the CI compiler.

## Demo and regression checks

Build Debug with PRODUCT_BUNDLE_IDENTIFIER=dev.opensource.MacSpaces.WebsiteDemo.
Launch with MACSPACES_WEBSITE_DEMO=1 and optionally MACSPACES_DEMO_OUTPUT.
The helper requires the separate bundle identifier, uses synthetic data, and
never reads real camera or clipboard content. Artwork paths are explicit in
WebsiteDemoCapture. Only safe, populated native Nook views are exported.

InteractionRegressionChecks verifies proportional fill, stacked sizing, new
widget persistence, the Nook-only sidebar and legacy style migration. Native
captures check empty/small profiles and physical camera clearance. Inspect
settings and the Gold, Midnight and Everforest scenes visually before shipping.
