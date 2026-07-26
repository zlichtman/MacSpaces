# MacSpaces

[![CI](https://github.com/zlichtman/MacSpaces/actions/workflows/ci.yml/badge.svg)](https://github.com/zlichtman/MacSpaces/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

MacSpaces is an open-source, native macOS control surface with two independent
spaces: OpenNotch and OpenDock. It is local-first, has no account or telemetry,
and runs as a menu-bar utility without occupying the system Dock or app
switcher.

<p align="center">
  <img src="docs/images/nook.png" width="900" alt="MacSpaces OpenNotch with Classic media, timer, and clock widgets in the Catppuccin palette">
</p>

> [!NOTE]
> MacSpaces 1.0.0 is the first public release. Report reproducible issues
> through GitHub Issues.

## Highlights

### OpenNotch and Tray

Build each Nook profile from an empty canvas, then resize and reorder its
widgets directly.

- Adapts to the built-in MacBook notch and provides a synthetic notch on other
  displays
- Customizable widget profiles with drag-and-drop reordering and resizing
- Timer, battery, and clock controls automatically pair as compact stacked
  cards when placed together
- Media controls, artwork, live audio bars, timers, calendar, reminders, notes,
  camera mirror, battery, Shortcuts, and clock widgets
- Toggleable full-width teleprompter for song lyrics (synchronized when
  available) and YouTube captions
- Compact live activities for music, timers, volume, display and keyboard
  brightness, microphone mute, Focus, charging, AirPods battery, and Bluetooth
  changes
- Persistent file Tray with drag-out, Finder reveal, AirDrop, and double-click
  open
- Hover, click, scroll, and two-finger gesture interactions
- Primary, all, or individually selected display targeting
- Hidden automatically during Mission Control so window previews stay clear

<p align="center">
  <img src="docs/images/live-activities.png" width="760" alt="MacSpaces compact timer and music live activities around a MacBook notch">
</p>

The collapsed Nook reserves balanced activity lanes only when something is
live. Music artwork and its animated signal stay together while a timer remains
glanceable on the opposite side.

<p align="center">
  <img src="docs/images/file-tray.png" width="900" alt="MacSpaces file drop Tray with staged files and quick actions">
</p>

Drop files onto the notch to stage them in the persistent Tray, then open,
reveal, remove, drag out, or share them without finding the original window.

### OpenDock

<p align="center">
  <img src="docs/images/widget-dock.png" width="900" alt="MacSpaces OpenDock with media, clock, calendar, and quick-action widgets">
</p>

- Independent bottom, left, or right placement
- Optional live window previews above Apple’s Dock, including minimized and
  hidden windows, with one-click exact-window focus
- Pinned running apps open the same live preview strip directly from OpenDock
- The App Switcher widget opens the same thumbnail browser for a visual
  alternative to an icon-only switcher
- Multiple profiles, duplicate widget instances, adaptive scrolling, and
  auto-hide
- A native per-app audio mixer with remembered volume, mute, activity meters,
  master output control, and no virtual-driver installation on macOS 14.2+
- Compact Timer, Clock, and Weather widgets pair into a single dock slot when
  placed next to one another
- Primary, all, or individually selected display targeting, with reliable
  wake and desktop-switch restoration
- 34 widget types, including:
  - Clock, weather, calendar with time-until badges, reminders, Now Playing,
    and detailed CPU, memory, disk, and battery statistics
  - Apps and folders, running apps, Shortcuts, Quick Actions, and clipboard
  - Notes, search, Pomodoro, bookmarks, converter, and color picker
  - Downloads, file shelf, screenshots, photos, mail, and voice memos
  - Hydration, progress, crypto, meetings, window controls, and layout tools

### Personalization

<p align="center">
  <img src="docs/images/appearance.png" width="840" alt="MacSpaces OpenNotch settings with the flat app icon and unified palette gallery">
</p>

- One visible palette gallery with 16 presets and one Custom color for each
  surface
- Per-surface intensity, contrast, opacity, glow, and corner radius
- Per-widget Classic, Glass, Terminal, Soft, Signal, Orbit, Mono, and Frame
  treatments; media and time widgets receive purpose-built layouts instead of
  a global skin
- Optional pairing is offered only after choosing a surface theme
- Visual add/remove cards replace setup wizards and dense widget menus; the app
  launches directly into its normal menu-bar experience

### Updates

MacSpaces checks GitHub Releases in the background. Automatic installation is
enabled by default and can be changed under About. A downloaded update must
match the installed bundle identifier and Developer ID team before MacSpaces
replaces and relaunches itself.

## Requirements

- macOS 13 Ventura or later. Per-app audio mixing requires macOS 14.2 or later.
  Live window thumbnails require macOS 14 or later; Ventura retains the window
  list, app icons, titles, and exact-window activation.
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build from source

```bash
git clone https://github.com/zlichtman/MacSpaces.git
cd MacSpaces
brew install xcodegen
make
open build/Build/Products/Release/MacSpaces.app
```

To work in Xcode:

```bash
xcodegen generate
open MacSpaces.xcodeproj
```

The generated Xcode project and all build output are intentionally ignored.
`project.yml` is the canonical project definition.

## Package a local build

```bash
make package
```

This creates `Releases/MacSpaces.dmg`. The packaging script:

- builds a universal Apple Silicon and Intel app;
- uses a local Developer ID or Apple Development identity when available;
- enables the hardened runtime;
- verifies the signed app after a DMG round trip; and
- falls back to ad-hoc signing when no signing identity is installed.

For a notarized local release, configure a `notarytool` keychain profile named
`MacSpaces`, then run:

```bash
MACSPACES_NOTARIZE=1 make package
```

No certificates, provisioning profiles, release images, or notary credentials
are stored in this repository.

## Permissions and privacy

MacSpaces requests permissions only when a related feature is used.

| Permission | Feature |
| --- | --- |
| Camera | Nook Mirror |
| Microphone | Voice Memo |
| Calendars | Calendar and meeting widgets |
| Reminders | Todos |
| Location | Local weather |
| Accessibility | Window Manager, Dock app detection, and exact-window focus |
| Screen Recording | Live window thumbnails |
| System Audio | Per-app volume and live mixer levels |
| Notifications | Completed timers and low-battery alerts |
| Automation | Media metadata fallback, Mail, and selected Mac actions |

Profiles, notes, Tray metadata, and other preferences remain on the Mac.
Clipboard history is memory-only, ignores concealed password-manager entries,
and is discarded when the app quits.

Network requests are limited to the feature being displayed:

- Open-Meteo for weather
- ipapi.co for approximate location when Location Services is unavailable
- CoinGecko for cryptocurrency prices
- Frankfurter for currency conversion
- YouTube image servers for artwork when a browser session is the active media
  source
- LRCLIB for synchronized lyrics, lyrics.ovh as its plain-lyrics fallback,
  and YouTube caption endpoints for the optional teleprompter
- GitHub Releases for signed update checks and downloads

System-wide now-playing metadata uses MediaRemote when the framework is
available. Because Apple restricts this private framework on newer macOS
versions, MacSpaces falls back to AppleScript for Music, Spotify, and supported
media in the active Safari, Chrome, or Edge tab. Spotify supplies the current
track identity; Spotify does not expose its in-app lyric text through the
public Web API, so the teleprompter resolves that track through LRCLIB and
lyrics.ovh. A brief continuity window keeps the player stable while the active
media source changes.

## Local data

MacSpaces stores its app data under:

```text
~/Library/Application Support/MacSpaces/
```

An existing OpenDock configuration can be imported on first launch. Future
changes are written only to the MacSpaces support directory.

## Project structure

```text
Sources/
  App/            App lifecycle, module coordination, shared services
  Debug/          Opt-in visual regression renderer
  DesignSystem/   Themes and reusable surface styling
  Modules/Notch/  Nook, Tray, gestures, widgets, and live activities
  Modules/Dock/   Profiles, window controller, and widget catalog
  Services/       Media, power, Bluetooth, calendar, weather, and crypto
  Settings/       Unified settings and permissions
Scripts/          Icon generation and signed release packaging
project.yml       Canonical XcodeGen project definition
```

## Visual QA

Debug builds include an opt-in offscreen renderer:

```bash
MACSPACES_VISUAL_QA=1 \
  build/Build/Products/Debug/MacSpaces.app/Contents/MacOS/MacSpaces
```

Regression captures are written to `/private/tmp/macspaces-visual-qa`.
Curated README states are written to
`/private/tmp/macspaces-readme-candidates`.

## Contributing

Issues and focused pull requests are welcome. Before opening a pull request:

```bash
xcodegen generate
xcodebuild \
  -project MacSpaces.xcodeproj \
  -scheme MacSpaces \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Please keep generated projects, build products, local app data, signing
material, and packaged releases out of commits.

## Attribution

MacSpaces is an independent open-source implementation inspired by the product
ideas behind NotchNook and CoolDock. It is not affiliated with lo.cafe,
dock.cool, Apple, or other referenced products. Product names and trademarks
belong to their respective owners. Music metadata and artwork shown inside the
demo interface belong to their respective rights holders.

## License

MacSpaces is available under the [MIT License](LICENSE).
