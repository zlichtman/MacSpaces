# MacSpaces

**Music, little tasks, and files. Right at your notch.**

[Website & demo](https://zlichtman.com/open-source#macspaces) · [Releases](https://github.com/zlichtman/MacSpaces/releases) · [Report an issue](https://github.com/zlichtman/MacSpaces/issues)

![MacSpaces 2.34 in the Everforest theme: Catacombs by Fog Lake playing, a countdown, the clock and the weather](Demos/2.x/screenshots/everforest-home.webp)

MacSpaces is a free, native menu-bar app that turns the notch into a small
workspace. Move the pointer to the notch to open the **Nook**: change the song,
join your next call, start a timer, jot a note or park a file. Move away, and it
tucks back in. Displays without a camera notch get a small synthetic one.

## Download

There are two versions. Pick the one for your Mac.

| | **MacSpaces 1.14** (stable) | **MacSpaces 2.34** (pre-release) |
| --- | --- | --- |
| Runs on | macOS 13 or later, Apple silicon and Intel | macOS 26 or later, Apple silicon |
| Download | [MacSpaces 1.14](https://github.com/zlichtman/MacSpaces/releases/download/v1.14/MacSpaces.dmg) | [MacSpaces 2.34](https://github.com/zlichtman/MacSpaces/releases/download/v2.34/MacSpaces.dmg) |
| Homebrew | `brew install --cask zlichtman/tap/macspaces` | `brew install --cask zlichtman/tap/macspaces@beta` |
| Updates | Built in | Paused in development builds; install new pre-releases |
| Read more | [1.14 README](https://github.com/zlichtman/MacSpaces/tree/v1.14#readme) | This page |

Both are signed and notarized. Open the disk image and drag **MacSpaces** into
**Applications**. With Homebrew you don't need `brew tap` first; installing by the
full name adds [the tap](https://github.com/zlichtman/homebrew-tap) for you. The two
versions share settings, so install one at a time.

MacSpaces runs in the menu bar, with no Dock icon or window. After installing, open
it once:

```sh
open -a MacSpaces
```

This page describes 2.34. The [1.14 README](https://github.com/zlichtman/MacSpaces/tree/v1.14#readme)
covers the stable version.

## What's new in 2.x

**A dock under the Nook.** The Nook hangs just below the notch, and a separate dock
under it opens full pages:

- **Music:** the cover beside the title, lyrics in your accent colour, a slim seek bar and big controls, tinted by the album art.
- **Calendar:** how far through the year you are, a month grid with coloured event dots, and your day with Join buttons.
- **Weather:** now, the next ten hours and the next four days, with feels-like, wind, humidity and rain.
- **Reminders, Notes, Timers, Clipboard, System, Coding and Tray.**

Choose which pages appear, and their order, in **Settings → Widgets → Dock**.

| | |
| --- | --- |
| ![The Music page in Everforest, playing Catacombs by Fog Lake](Demos/2.x/screenshots/everforest-music.webp) | ![The Calendar page in KemoSabe, with year progress, a month grid and today's events](Demos/2.x/screenshots/kemosabe-calendar.webp) |
| **Music** in Everforest, with Catacombs by Fog Lake | **Calendar** in KemoSabe |

![The Weather page in the MacSpaces theme, with hourly and four-day forecasts](Demos/2.x/screenshots/midnight-weather.webp)

**Widgets in three sizes.** Every Home widget can be Small, Medium or Large.
Small widgets next to each other share a column, so you decide which ones pair
up. Right-click a widget and choose **Size**, or use **Settings → Widgets**.

| | |
| --- | --- |
| ![Home in KemoSabe: a large Calendar with a month grid, Reminders, the clock and a focus timer](Demos/2.x/screenshots/kemosabe-home.webp) | ![Home in the MacSpaces theme: a large Weather forecast, Notes, Clipboard and Keep Awake](Demos/2.x/screenshots/midnight-home.webp) |

**Widgets that do more.**

- **Calendar:** your current or next event, with a **Join** button for Zoom, Meet, Teams and other video calls.
- **Reminders:** check them off right in the tile.
- **Timer:** custom lengths, pause and +1 minute. **Focus timer:** your own focus and break lengths.
- **Clipboard:** click a recent clip to copy it again.
- **Notes:** your latest notes, and a one-click New.
- **Weather:** a four-day forecast on Large, in °C or °F.
- **Clock:** 24-hour time, seconds, and a second time zone.
- **Keep Awake:** one tap, for 15 minutes, an hour, two hours, or until you stop it.
- **Quick Actions:** labelled buttons, now with Lock and Display off.
- **Messages and Tsukumo:** reply to messages and send quick tasks from the Nook.

**Themes.** Five app themes (MacSpaces, PowderMeet, Heartable, KemoSabe and Tsukumo)
and a palette collection including Everforest, each with light and dark versions.
The screenshots above show Everforest, KemoSabe and MacSpaces.

**Calendar credit.** The year progress bar and month grid follow Aaron Lichtman's
DayDrop menu-bar calendar.

**Settings that show what you'll get.** **Settings → Widgets** draws your Home layout
to scale, with each widget's size and options. **Settings → Permissions** lists the
widgets that use each permission.

![The Home layout editor in Settings](Demos/2.x/screenshots/settings-widgets.webp)

## Privacy

MacSpaces has no account and no analytics. A widget asks for access only when you
add it: Camera for Mirror, Location for Weather (with an approximate IP fallback),
Calendars and Reminders for their widgets, Bluetooth for Battery, Automation for
media details, Quick Actions and Messages, and Full Disk Access only if you turn on
incoming Messages.

Clipboard history stays in memory unless you choose to keep it, and copies that
password managers mark as concealed or transient are never recorded. The app
contacts only the services its features use: Open-Meteo and ipapi.co for weather,
LRCLIB and lyrics.ovh for lyrics, and GitHub for updates.

## Build from source

Install Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run:

```sh
git clone https://github.com/zlichtman/MacSpaces.git
cd MacSpaces
make
```

That builds 2.34. For 1.14, run `git checkout v1.14` before `make`. The
[engineering guide](AGENTS.md) covers architecture, checks and releases.

## Contribute

[Open an issue](https://github.com/zlichtman/MacSpaces/issues) with your macOS
version, MacSpaces version (**Settings → General**) and the steps to reproduce a
problem. Pull requests are welcome. MacSpaces is free and open source under the
[MIT license](LICENSE).
