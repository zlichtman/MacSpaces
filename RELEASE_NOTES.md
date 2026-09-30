# MacSpaces 2.36 (pre-release)

**2.36** is a development build for macOS 26 and Apple Silicon. The stable
release is 1.14; 2.36 does not replace it and installed 1.x copies are not
offered it as an update.

New since 2.35:

- **Automatic updates for 2.x:** MacSpaces now checks GitHub for new 2.x pre-releases while it runs, downloads them, verifies the signature and asks before restarting to install. Settings → General → Updates has Check Now and the download switch. Earlier 2.x builds can't update themselves, so install 2.36 once by hand; later versions arrive on their own.
- **Rounded app logo** in Settings.

Also in recent 2.x releases: Noir, Rosé Pine, Kanagawa, Ayu and Custom themes; a low-battery warning for Claude Code and Codex; battery health, cycles and charger details; moving sound bars in the notch; a Settings window that fits any size; a dock of pages (Music, Calendar with year progress, Weather, Reminders, Notes, Timers, Clipboard, System, Coding and Tray); and Small/Medium/Large widgets.

Installed with Homebrew? The app updates itself, and `brew upgrade --cask zlichtman/tap/macspaces@beta` still works.
