# MacSpaces

[![CI](https://github.com/zlichtman/MacSpaces/actions/workflows/ci.yml/badge.svg)](https://github.com/zlichtman/MacSpaces/actions/workflows/ci.yml)

A useful little Nook at the top of your Mac. Music, weather, focus timers, notes
and files, in a native panel that opens from the notch.

[Download MacSpaces](https://github.com/zlichtman/MacSpaces/releases/latest/download/MacSpaces.dmg)

macOS 13 or later · Apple silicon and Intel · Signed and notarized · MIT licensed

## Your Nook

- One modern widget style, with Midnight, Everforest and other coordinated themes.
- Widgets fill the available space, including on physical notches that need room
  for the camera. Small and empty profiles keep the add-widget button accessible.
- Music, Weather with hover details, Calendar, Todos, Timer, Pomodoro, Clipboard,
  Notes, Quick Actions, Shortcuts, Battery, Clock and an optional Camera Mirror.
- Drag to reorder widgets; right-click to move or remove them. Create profiles
  for work, listening or a quieter desktop.
- Drop files onto the notch to open the Tray, then drag them into another app.
- Compact live activities for music, timers, power and supported system controls.
- Battery details for your Mac and connected devices, including separate earbud
  and case readings when macOS reports them. Plugged in and charging are distinct.
  Device notifications resize to keep names and percentages visible.
- Settings are organized into General, Widgets, Appearance and Activities.
  Widget access appears with the widgets that need it; About & Updates is separate.

Version 1.1 focuses entirely on the Nook. Existing profiles and settings are
preserved; legacy style choices
use the modern widget style.

## Install

Open the downloaded disk image and drag MacSpaces to Applications, replacing an
older copy if present. Launch MacSpaces from Applications. Use its menu-bar menu
for settings and updates. A notch is optional: other screens use a synthetic one.

Permissions are requested by the feature that needs them. Camera is only for
Mirror, Location is for Weather, and Calendar/Reminders are for their widgets.
Clipboard history stays in memory and ignores concealed/transient entries from
password managers. There is no account or telemetry.

## Build and release

Install Xcode and XcodeGen, then run `make`. `project.yml` is the canonical project.

`make release` builds both architectures, signs with Developer ID, notarizes and
staples the app and DMG using the `MacSpaces` Keychain profile, then verifies
Gatekeeper acceptance. See [AGENTS.md](AGENTS.md) for engineering details.

Report reproducible problems through [GitHub Issues](https://github.com/zlichtman/MacSpaces/issues).
