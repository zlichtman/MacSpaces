# MacSpaces 1.14

**Music, little tasks, and files. Right at your notch.**

[Download MacSpaces 1.14](https://github.com/zlichtman/MacSpaces/releases/download/v1.14/MacSpaces.dmg) · [Website & demo](https://zlichtman.com/open-source#macspaces) · [All releases](https://github.com/zlichtman/MacSpaces/releases)

![The MacSpaces Nook with weather, music, a clock, and clipboard history](Demos/nook-gold.webp)

MacSpaces is a free, native menu-bar app that turns the notch into a small
workspace. Move the pointer to the top of the screen to open the **Nook**. You can
change the song, start a timer, jot a note or check the weather there. Switch to
**Tray** to park a file between apps. Move away, and the Nook tucks back into the notch.

No camera notch? MacSpaces adds a small synthetic one to other displays.

**macOS 13 or later · Apple silicon and Intel · Signed and notarized · MIT licensed**

## Install

1. [Download MacSpaces 1.14](https://github.com/zlichtman/MacSpaces/releases/download/v1.14/MacSpaces.dmg).
2. Open the disk image and drag **MacSpaces** into **Applications**.
3. Open MacSpaces. It runs in the menu bar, with no Dock icon or window.

Or use Homebrew. You don't need `brew tap` first; installing by the full name
adds the tap for you:

```sh
brew install --cask zlichtman/tap/macspaces
open -a MacSpaces
```

MacSpaces comes from its own tap, [zlichtman/homebrew-tap](https://github.com/zlichtman/homebrew-tap),
not from Homebrew's official cask list.

Installed 1.0.0? It's the same app, now named 1.14. There's nothing to update.

## The Nook

The Nook is a set of widgets you choose. Add, remove and reorder them in
**Settings → Widgets**, and save profiles for different parts of your day. Small
widgets stack beside larger ones, and the Nook sizes itself to fit.

| | Widgets |
| --- | --- |
| **Listen** | **Media** for Apple Music, Spotify, and YouTube, SoundCloud, Bandcamp, Vimeo or Twitch in Safari, Chrome or Edge. **Audio Controls** set per-app volume (macOS 14.2+). |
| **Plan** | **Calendar** (today's events), **Todos** (Reminders), **Weather**, **Clock** |
| **Focus** | **Timer**, **Pomodoro**, **Notes**, **Keep Awake** |
| **Do** | **Clipboard** history, **Shortcuts**, **Quick Actions**: dark mode, lock screen, screenshot a selection, empty Trash, screen saver |
| **Check** | **Battery** for your Mac and paired Bluetooth accessories, with earbuds and case shown separately. **System Stats** and an optional camera **Mirror**. |

**Lyrics and captions.** Turn on the caption bar to show the current synced
lyric line under your widgets, or the caption line for a YouTube video.

## While the notch is closed

The closed notch shows compact live activities: the playing song, a running
countdown, charging, volume, display and keyboard brightness, microphone mute,
and Focus. Turn each one on or off in **Settings → Activities**.

## Tray

![Files held in the MacSpaces Tray](Demos/tray-everforest.webp)

Drag a file to the notch and pause for a moment to open **Tray**. Preview it with
Quick Look, open it, share it, compress it into a ZIP, or drag it into another
app. Tray keeps a reference, so your original file never moves.

## Themes

![MacSpaces in the Midnight theme](Demos/nook-midnight.webp)

Pick **MacSpaces, PowderMeet, Heartable, KemoSabe or Tsukumo**, or a classic
palette such as Catppuccin, Dracula, Everforest, Gruvbox, Nord, Solarized or
Tokyo Night. Each has light and dark versions and follows one
**System / Light / Dark** setting. Animations respect Reduce Motion.

## Privacy

MacSpaces has no account and no analytics. A feature asks for access only when
you turn it on: Camera for Mirror, Location for Weather (with an approximate IP
fallback), Calendars and Reminders for their widgets, Bluetooth for Battery, and
Automation for media details and Quick Actions.

Clipboard history stays in memory, and copies that password managers mark as
concealed or transient are never recorded. The app contacts only the services
its features use: Open-Meteo and ipapi.co for weather, LRCLIB and lyrics.ovh for
lyrics, and GitHub for updates.

## MacSpaces 2.33 (pre-release)

MacSpaces 2.33 is the next version, for macOS 26 on Apple silicon. It adds a dock
with Music, Calendar, Notes, Weather and Tray pages, widget sizes, and many
widget upgrades. It's a development build, so 1.14 stays the default download.
See the [2.33 release](https://github.com/zlichtman/MacSpaces/releases/tag/v2.33)
or install it with `brew install --cask zlichtman/tap/macspaces@beta`.

## Build from source

Install Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run:

```sh
git clone https://github.com/zlichtman/MacSpaces.git
cd MacSpaces
git checkout v1.14
make
```

The [engineering guide](AGENTS.md) covers architecture, checks and releases.

## Contribute

[Open an issue](https://github.com/zlichtman/MacSpaces/issues) with your macOS
version, MacSpaces version (**Settings → General**) and the steps to reproduce a
problem. Pull requests are welcome. MacSpaces is free and open source under the
[MIT license](LICENSE).
