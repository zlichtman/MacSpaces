<div align="center">

# MacSpaces

**MacSpaces turns your notch into a workstation.**

[![Release](https://img.shields.io/github/v/release/zlichtman/MacSpaces?label=release&color=ff5c8a)](https://github.com/zlichtman/MacSpaces/releases/latest)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](#install)
[![Apple Silicon + Intel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-555)](#install)
[![Signed and notarized](https://img.shields.io/badge/signed%20%26%20notarized-Developer%20ID-2ea44f)](#install)
[![Homebrew](https://img.shields.io/badge/Homebrew-cask-fbb040?logo=homebrew&logoColor=white)](#install)
[![MIT License](https://img.shields.io/github/license/zlichtman/MacSpaces?color=blue)](LICENSE)

[Website](https://www.zlichtman.com/macspaces) · [Download](https://github.com/zlichtman/MacSpaces/releases/latest/download/MacSpaces.dmg)

<img src="Demos/screenshots/home.webp" alt="Home in Snow: I Melt With You by Modern English, a small timer, the clock and Keep Awake" width="100%">

</div>

Hover the notch to open your workspace. Free, open source, on any Mac.

## Install

[Download MacSpaces.dmg](https://github.com/zlichtman/MacSpaces/releases/latest/download/MacSpaces.dmg), or:

```sh
brew install --cask zlichtman/tap/macspaces
```

## Pages

<table>
<tr>
<td width="50%"><img src="Demos/screenshots/music.webp" alt="Music with synced lyrics"><br><b>Music</b>: lyrics, stats and backups</td>
<td width="50%"><img src="Demos/screenshots/calendar.webp" alt="Calendar"><br><b>Calendar</b>: your month and day</td>
</tr>
<tr>
<td><img src="Demos/screenshots/coding.webp" alt="Agents"><br><b>Agents</b>: Claude Code and Codex</td>
<td><img src="Demos/screenshots/usage.webp" alt="Usage"><br><b>Usage</b>: tokens and limits</td>
</tr>
<tr>
<td><img src="Demos/screenshots/weather.webp" alt="Weather"><br><b>Weather</b></td>
<td><img src="Demos/screenshots/clock.webp" alt="Clock"><br><b>Clock</b>: your places on a globe</td>
</tr>
<tr>
<td><img src="Demos/screenshots/timers.webp" alt="Timers"><br><b>Timers</b></td>
<td><img src="Demos/screenshots/meetings.webp" alt="Meetings"><br><b>Meetings</b>: mute and camera</td>
</tr>
<tr>
<td><img src="Demos/screenshots/dictation.webp" alt="Dictation"><br><b>Dictation</b></td>
<td><img src="Demos/screenshots/prompter.webp" alt="Teleprompter"><br><b>Teleprompter</b>: hidden when sharing</td>
</tr>
<tr>
<td><img src="Demos/screenshots/shortcuts.webp" alt="Shortcuts"><br><b>Shortcuts</b></td>
<td><img src="Demos/screenshots/notes.webp" alt="Notes"><br><b>Notes</b></td>
</tr>
<tr>
<td><img src="Demos/screenshots/system.webp" alt="System"><br><b>System</b>: battery and stats</td>
<td><img src="Demos/screenshots/tray.webp" alt="Tray"><br><b>Tray</b>: files held in the notch</td>
</tr>
<tr>
<td><img src="Demos/screenshots/wisp-hello.webp" alt="Wisp's greeting"><br><b>Wisp</b>: ask in plain words</td>
<td><img src="Demos/screenshots/wisp.webp" alt="Wisp with Claude adding a reminder and a tea timer"><br><b>Wisp</b>: any model, your own key</td>
</tr>
</table>

## Clipboard and Files

<table>
<tr>
<td width="33%"><img src="Demos/screenshots/clipboard.webp" alt="Clipboard history"></td>
<td width="33%"><img src="Demos/screenshots/converter-poster.webp" alt="The File Converter wheel"></td>
<td width="33%"><img src="Demos/screenshots/basket.webp" alt="A file basket holding three files"></td>
</tr>
</table>

- **Clipboard:** find, pin and paste your history with ⇧⌘C
- **File Converter:** hold Shift while dragging to convert
- **File baskets:** park one anywhere, drop files on it, drag or AirDrop them together

## Themes

<table>
<tr>
<td width="33%"><img src="Demos/screenshots/themes-terminal.webp" alt="The Terminal drawer: colour pills for every theme"></td>
<td width="33%"><img src="Demos/screenshots/themes-macspaces.webp" alt="The MacSpaces drawer: 25 live scenes"></td>
<td width="33%"><img src="Demos/screenshots/themes-custom.webp" alt="The Custom drawer: solid, two-tone, glass or a picture"></td>
</tr>
</table>

- **Terminal:** Noir and editor favourites, plus every Ghostty and iTerm2 theme
- **MacSpaces:** 25 live scenes, from flowers and forests to night skies and neon
- **Custom:** solid, two-tone, glass or your own picture

## Privacy

- No account, no analytics, no ads
- Access is asked for only when you turn a feature on
- Anything saved about you is encrypted on your Mac
- Spotify and Wisp's models connect only with your own app or key

## Build

- Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen), then `make`
- [Engineering guide](docs/ENGINEERING.md) · [Report an issue](https://github.com/zlichtman/MacSpaces/issues)

## Credits

- [MIT License](LICENSE)
- Calendar design from Aaron Lichtman's DayDrop
- Terminal by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
