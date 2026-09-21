# MacSpaces engineering guide

This document describes how MacSpaces is built: the module layout, the two
surfaces, the services behind them, and the signing and release pipeline.
`README.md` covers installation and use.

## Overview

MacSpaces is a native macOS menu-bar utility (`LSUIElement`) written in Swift
with AppKit and SwiftUI, plus one Objective-C++ audio engine. It hosts two
independent surfaces that share services and a design system:

- **OpenNotch** (the Nook): a panel that unfolds from the MacBook notch, or a
  synthetic notch on other displays. Widget profiles, the file Tray, the
  teleprompter, the camera mirror, and compact live activities.
- **OpenDock**: an independent dock on any screen edge with 34 widget types,
  live window previews, and a per-app audio mixer.

Everything is local-first. There is no account, no telemetry, and the only
network traffic is the feature being displayed (see *Network* below).

Toolchain: Swift 5.9, macOS 13 deployment target, Xcode 15+, XcodeGen.
`project.yml` is the canonical project definition; the generated
`MacSpaces.xcodeproj` is ignored.

## Module map

```text
Sources/
  App/            MacSpacesApp (entry), ModuleCoordinator (owns both surfaces),
                  AppServices (shared service container), AppSettings
  DesignSystem/   Design (tokens, surfaces, treatments), ThemeStore (palettes)
  Modules/Notch/
    Core/         NotchGeometry, NotchManager (per-display windows),
                  NotchViewModel (state, sizing, live-activity lanes), NotchWindow
    UI/           NotchContainerView, NotchHeaderView, NotchShape, ScrollWheelCatcher
    Features/
      LiveActivities/  Compact music, timer, volume, brightness, Focus,
                       charging, AirPods and Bluetooth cards
      Media/           MediaPlayerView, AudioSpectrumView
      Mirror/          Camera mirror tab
      Shelf/           ShelfStore + ShelfView (the persistent file Tray)
      Teleprompter/    Lyrics and caption bar
      Widgets/         NookDashboardView, NookWidgetsView (profiles, drag/resize)
    Settings/     NookSettings, NookSettingsPane
  Modules/Dock/
    Core/         DockStore (profiles, persistence), DockController, DockWindow, WidgetKind
    UI/           DockContainerView, VisualEffectView
    Widgets/      One file per widget (Apps, AppSwitcher, AudioControls, Bookmarks,
                  Calendar, Clipboard, Clock, ColorPicker, Converter, Downloads,
                  DrinkWater, Emoji, FileShelf, Mail, Notes, NowPlaying, Photos,
                  Pomodoro, Progress, QuickActions, Reminders, Screenshots, Search,
                  Shortcuts, SystemStats, VoiceMemo, Weather, ModernWidgets)
                  Support/ FileDrop, FolderScanner, WidgetEmptyState
  Services/       Shared, surface-agnostic services (below)
  Settings/       SettingsView, SettingsWindowController, DisplayTargeting
  Onboarding/     First-launch import of an existing OpenDock configuration
  Debug/          VisualQAHarness (opt-in offscreen renderer, Debug only)
  Resources/      Info.plist, entitlements, asset catalog, app icon
  Support/        Objective-C bridging header
Scripts/          generate-app-icon.swift, package-release.sh
Demos/            Screenshots used on the website
```

### Ownership rules

- `ModuleCoordinator` is the only object that creates the Nook and Dock
  controllers and wires them to `AppServices`. Surfaces never reach into each
  other; anything shared lives in `Services/`.
- Per-display window management belongs to `NotchManager` and `DockController`.
  Views never create windows.
- `WidgetKind` is the single catalog of dock widgets: its cases drive the add
  menu, persistence keys, default sizing, and the view factory in
  `DockContainerView`. Adding a widget means one new case plus one view file.
- Persistence is JSON under `~/Library/Application Support/MacSpaces/`
  (profiles, notes, Tray metadata, settings). Clipboard history is memory-only.

## Services

| Service | Role |
| --- | --- |
| `NowPlaying/` | `NowPlayingController` picks the active source: `MediaRemoteProvider` (private framework, when available), `AppleScriptProvider` (Music, Spotify), `BrowserMediaProvider` (Safari, Chrome, Edge tab). A short continuity window keeps the player stable while sources change. |
| `AudioMixerEngine.h/.mm`, `AudioMixerService` | Per-app volume, mute, and level meters through Core Audio process taps (macOS 14.2+). No virtual audio driver. |
| `TeleprompterService` | Synchronized lyrics from LRCLIB, plain lyrics from lyrics.ovh, YouTube captions for browser media. Identifies itself with a `MacSpaces 1.0.0` User-Agent. |
| `UpdateService` | Polls `api.github.com/repos/zlichtman/MacSpaces/releases/latest`, downloads the DMG, and only installs it if the bundle identifier and Developer ID `TeamIdentifier` match the running app. Automatic install is a user setting. |
| `WindowPreviewService` | ScreenCaptureKit thumbnails for live window previews and exact-window focus (macOS 14+; Ventura keeps titles and activation). |
| `BluetoothMonitor` | Connection and battery changes for already-paired devices; feeds a live activity. |
| `PowerSourceMonitor`, `SystemActivityMonitor`, `SystemStatsService` | Charging, brightness, Focus, CPU, memory, disk, battery. |
| `CalendarService`, `WeatherService`, `CryptoService`, `ShortcutsService`, `QuickActions`, `AppleScriptRunner`, `ClipboardMonitor`, `TimerService` | Widget backends. |

### Network

Requests are made only by the widget or feature on screen: Open-Meteo
(weather), ipapi.co (approximate location fallback), CoinGecko (crypto),
Frankfurter (currency), YouTube image and caption endpoints (browser media),
LRCLIB and lyrics.ovh (lyrics), and GitHub Releases (updates).

### Permissions

Each permission is requested lazily by the feature that needs it: Camera
(Mirror), Microphone (Voice Memo), Calendars and Reminders (widgets),
Location (weather), Accessibility (window management and exact-window focus),
Screen Recording (window thumbnails), System Audio (mixer), Notifications
(timers, low battery), Automation (AppleScript media fallback, Mail, quick
actions). Usage strings live in `project.yml` under `info.properties`.

## Signing and release

- Bundle id `dev.opensource.MacSpaces`, team `28LJG7MXT3`, version in
  `project.yml` (`CFBundleShortVersionString`, `CFBundleVersion`).
- Hardened runtime is on. The app is **not** sandboxed (it needs Accessibility,
  ScreenCaptureKit, and Apple Events). Entitlements
  (`Sources/Resources/MacSpaces.entitlements`): `automation.apple-events`,
  `device.audio-input`, `device.camera`.
- `make` builds an unsigned Release app for local use. `make package` runs
  `Scripts/package-release.sh`, which:
  1. generates the project into a staging directory and builds a universal
     (`arm64 x86_64`) Release app with code signing disabled;
  2. signs it with `MACSPACES_SIGNING_IDENTITY`, else the first
     `Developer ID Application` identity, else `Apple Development`, else ad hoc;
     Developer ID signatures get a secure timestamp;
  3. with `MACSPACES_NOTARIZE=1`, zips and submits the app to
     `xcrun notarytool` using the keychain profile named by
     `MACSPACES_NOTARY_PROFILE` (default `MacSpaces`), then staples it;
  4. builds `MacSpaces.dmg` (UDZO, `/Applications` symlink), signs the image,
     notarizes and staples it too when enabled;
  5. mounts the image and verifies the signature and both architectures, plus
     stapling and Gatekeeper acceptance when notarization is enabled, before
     moving it to `Releases/MacSpaces.dmg` (ignored by git).
- `make release` enables notarization; `make package` remains a local build.
- A public release must be notarized: Gatekeeper rejects a Developer ID
  signature without a ticket (`spctl -a -t open --context
  context:primary-signature MacSpaces.dmg` must say `accepted`). Store the
  credential once with `xcrun notarytool store-credentials MacSpaces --key
  <AuthKey.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>`.
- Publish the DMG as a GitHub Release tagged `vX.Y.Z`; `UpdateService` reads
  the latest release, so the DMG asset name must stay `MacSpaces.dmg`.

## CI

`.github/workflows/ci.yml` runs on every push and pull request on `macos-14`:
install XcodeGen, generate the project, build Release with signing disabled,
and upload the unsigned `.app` as an artifact. Releases are packaged locally.

## Visual QA

Debug builds include an opt-in offscreen renderer:

```bash
MACSPACES_VISUAL_QA=1 \
  build/Build/Products/Debug/MacSpaces.app/Contents/MacOS/MacSpaces
```

Regression captures are written to `/private/tmp/macspaces-visual-qa` and
curated README states to `/private/tmp/macspaces-readme-candidates`. The
screenshots in `Demos/` come from this renderer.

## Contributing checklist

```bash
xcodegen generate
xcodebuild -project MacSpaces.xcodeproj -scheme MacSpaces -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Keep generated projects, build products, local app data, signing material, and
packaged releases out of commits (`.gitignore` already covers them).

## Website demo captures

`WebsiteDemoCapture` renders distinct overview, Nook, and Dock scenes from native
views. It also checks empty, single-widget, and paired-widget profiles against
the physical notch, plus the below-notch fallback on constrained displays.
Build Debug with `PRODUCT_BUNDLE_IDENTIFIER=dev.opensource.MacSpaces.WebsiteDemo`
and launch with `MACSPACES_WEBSITE_DEMO=1`. The separate bundle identifier is
required to isolate demo settings. Supply `MACSPACES_DEMO_ARTWORK` with the path
to the Pillow Lips album cover and optionally `MACSPACES_DEMO_OUTPUT` for output.
The Everforest demo uses the app's custom palette support (#2D353B / #A7C080).
