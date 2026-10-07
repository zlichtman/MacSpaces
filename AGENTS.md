# MacSpaces engineering guide

MacSpaces is a native macOS menu-bar app focused on the Nook. A panel opens
from the physical camera notch, or a synthetic notch on other displays. It has
widget profiles, a file Tray, compact live activities, optional Mirror, and lyrics.

## Current development state

The working tree is **2.80** (build 80), macOS 15+ on Apple silicon and Intel. It is
the official release (GitHub Latest). 1.x is retired (2026-10-01): it is no longer
offered on the website, in Homebrew or in the README; **1.14** remains the parent commit. See Documentation/BUILD-STATUS.md and the
95-entry feature audit before claiming any 2.x capability is complete.
From 2.38, 2.x builds no longer set MacSpacesDevelopmentBuild: they read
releases/latest and can be published with Scripts/publish-release.sh. 2.36 and
2.37 carry the flag and read the release list, which includes official releases.

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
  Menus and the library list widgets alphabetically (`NookWidgetKind.alphabetical`).
  The Audio (per-app volume) widget was removed in 2.46 with its mixer and Core
  Audio engine; saved profiles drop it on decode.
- `Sources/DesignSystem`: shared appearance and palette persistence. Only the
  modern widget style is selectable; old style identifiers decode to it.
  `Design` owns the motion tokens (open/close/hover springs, `nookDepth`
  transitions) and optional trackpad `Haptics`; all of them honor Reduce Motion.
- `Sources/Settings`: General (enable, startup, behavior, displays, software
  updates), Widgets (profiles, visual editor, lyrics, relevant access),
  Appearance (theme, accessibility), Permissions, and Activities. There is no About page;
  the installed version appears with software updates in General. Permissions are reviewed in the dedicated Permissions page; opening it does not request access.
  The Settings window can grow but not shrink below 980×680 (less only on a short
  screen); tiling that squashes it is undone. Settings remember the current destination; Nook shortcuts open the relevant page.
- `Sources/Services`: media, weather, calendar, clipboard, timers and related tools.
- `Sources/Debug`: isolated demo rendering and regression assertions.

MacSpaces has no Tsukumo integration (removed in 2.43 at the owner's request, along
with the bridge): Tsukumo is its own Mac app with a side dock. Coding features are
welcome again (owner, 2026-10-05): they belong on the Terminal page.
Saved docks drop the retired pages on decode.

Nook columns grow proportionally to fill available width. Adjacent compact
widgets can stack. Oversized profiles retain useful tile widths and scroll.
The dock's app pages are user-configurable (`NookSettings.dockApps`); Home and
Settings are always present, and file drops still open Tray when it is hidden.
With two or more Home profiles, a third dock capsule (between the pages and
Settings) holds one button per profile with its own symbol (`NookProfile.symbol`,
chosen in Settings → Widgets → Profiles → Icon; defaults by position); clicking
one switches profile and opens Home. With one profile, Home stays beside Settings.
Refresh buttons use `RefreshButton`, whose arrow turns once per click.
Panel sizing follows the active content and display, with fixed visual proportions. Legacy manual sizing preferences are retained for compatibility but do not control geometry. A detached navigation dock sits below the panel. Content starts below the physical camera cutout; the shared hover region includes the gap to the dock. Empty profiles keep Add Widget.
Hover and scroll never open the Nook while Mission Control or App Exposé shows
(`MissionControl.isActive`: full-screen WindowManager overlay windows, or Dock ones
below its own level on earlier macOS); a click still does. An open Nook checks
about three times a second (≈1 ms each) and closes when Mission Control appears,
since it would otherwise sit over the Spaces bar.
The File Converter (menu → File Converter; General → File Converter) shows a frosted
wheel around the pointer when a file drag is under way and Shift is held: formats for
that kind of file, or tools with Option-Shift (compress, metadata, resize, extract
audio, GIF, snapshot, split/merge PDFs, zip/unzip). `ConverterWheel` watches global
mouse drags (hit-testing uses the drag location in the panel's unflipped window coordinates) and the drag pasteboard (no permission); `FileConverter` uses only ImageIO,
PDFKit, AVFoundation, NSAttributedString and ditto/zip, offers only formats this Mac
can write (no MP3, MKV, WebM, OGG or RAR), and saves copies beside the original (or in
Downloads when that folder is read-only); `ConverterJobs` shows progress cards and
reveals results in Finder. MACSPACES_QA_SCOPE=converter with MACSPACES_CONVERTER_INPUT
runs every action on a folder of samples. The menu-bar menu reads: Nook, File
Converter, File Baskets | Settings | Check for Updates | Quit (no ellipses).
File baskets (menu → File Baskets) are frosted circles parked anywhere (default:
the bottom-right corner beside the Dock); drop files on one, click to open it into
a panel that grows away from the nearest corner, drag to move. Folding it puts the
circle back exactly where it was (the open panel may sit higher to clear the Dock).
Remove Basket (the circle's right-click menu, a submenu naming each basket in the
panel's basket menu, or a basket chip on the Tray page) deletes its list and place;
baskets hold references, so files are untouched. The Nook's Tray page
(`TrayPageView`) shows chips for the Tray and each basket when any exist; baskets
share one `ShelfStore` per basket (`BasketWindowController.store(for:)`). Positions and open
baskets persist (`fileBaskets.origin.<id>`, `fileBaskets.open`). MACSPACES_QA_SCOPE=basket.
File drags open Tray only after pausing in a small zone around the closed notch
(General → "Open Tray when dragging files to the notch" turns this off).

Widgets that need room also have a dock page: Terminal (the same shell as the
widget; only the most recently shown host holds the terminal view), Shortcuts
(search and run every Shortcut, with the six quick actions) and Mirror (a larger
preview; the camera runs only while it shows). Battery and Keep Awake live on
the System page.

The Music page sets the current lyric in a `LyricStyle` chosen in Settings →
Appearance → Lyrics (previews in the theme's colours): Classic, Poster (the
longest word as a condensed headline, on a plain background) and Choreography (words step in; only when
theme effects animate and Reduce Motion is off). Styles use only
the theme's accent and ink. 2.46's Stanza stage, Waterformed and Psychedelic
bloom were dropped in 2.47 and read back as Classic. MACSPACES_QA_SCOPE=lyric-styles
captures every style.
LRCLIB matches must agree on title and artist (edition suffixes and features
ignored); timed lyrics from a recording of another length lose to the right cut,
and a free-text search runs before the plain-lyrics fallback. Intros and blank LRC
lines clear the lyric (nothing shows); `[offset:]` tags apply.
Lyrics and the progress bar share one clock, `NowPlayingController.estimatedElapsed`;
lines switch `TeleprompterService.leadTime` (0.25 s) early. MediaRemote's elapsed
time is as of its timestamp, so the provider advances it to the moment of reading,
and the estimate's read time moves only when the stored elapsed time does.

The Terminal widget (`.terminal`, medium or large) runs quick commands in one login
shell inside the Nook (`QuickShell`, rendered by SwiftTerm). A command typed in its
bar is sent to the shell with Return; swiping up on the bar (or ↑) steps through
earlier commands (history kept in `terminal.history`, clearable). The shell keeps
running when the Nook closes and stops only when the widget leaves Home. Clicking
the output gives it the keyboard for prompts. A closed Nook hands the keyboard back
to the active app (NotchManager reorders a key NotchWindow on collapse), and the
Nook stays open while the bar holds unsent text. Widget keys (Delete, ⌘Z, Escape)
are ignored while any text input, including the terminal, has focus.

Service demand follows enabled Nook widgets. A page's services keep running for
four seconds after it closes (`lingeringTabs`), so closing never stops them
mid-animation and a quick reopen finds them warm; opening starts them at once. Clipboard history is memory-only
unless "Keep history after quitting" is on, and excludes concealed/transient pasteboard
types and text shaped like a credential (`ClipboardSecrets`: private keys, prefixed
tokens, JWTs). The paste queue (list button on the Clipboard page and widget; off by
default) queues every copy, and each ⌘V or ⌥⇧⌘V puts the next clip on the clipboard
0.2 s later, in order or newest first. Seeing ⌘V in other apps needs Accessibility,
requested only when the queue is turned on; the clipboard service runs while it's on.
The closed Nook shows only a count, never clip contents. Turning it off puts the last
copy back. Scripts/check-clipboard.sh covers the queue and credential filter;
MACSPACES_QA_SCOPE=clipboard-queue captures it.
Clipboard history anywhere (Maccy-style): `ClipboardPopup` registers a Carbon global
hot key (`ClipboardPreferences.shortcut`, default ⇧⌘C; no permission) and shows a
non-activating key panel (`ClipboardPopupView`) at the pointer, centre or under the
notch; a local key monitor handles ↑↓/⇧/⌘ navigation, ↩ copy, ⌥↩ paste, ⌥⇧↩ plain
text, ⌘/⌥1–9, ⌥P pin, ⌥⌫ delete, ⌥⌘⌫ clear, ⌃U, ⌘, and Escape. Pasting writes the
clips (several are joined by new lines), reactivates the previous app and posts ⌘V
(Accessibility, prompted on first use; without it clips are only copied).
`ClipboardPreferences` (Settings → Clipboard, its own destination) holds history size
(default 200), sort (last/first/most copied), search mode (exact, fuzzy, regex, mixed:
the first that matches anything), pins top/bottom, preview and app icons, pause and
ignore-next, clear on quit, clear the system clipboard, and `ClipboardFilter`: record
text/images/files, ignored apps (or only listed apps), ignored regex patterns and
ignored pasteboard types (Maccy's defaults). Entries carry `firstDate` and
`copyCount` (older saved history decodes with defaults). The shortcut keeps the
clipboard service running. MACSPACES_QA_SCOPE=clipboard-popup captures the popup and
settings; clipboard-popup-live drives the real panel (focus, search, arrows, Escape). Weather starts only when its
widget is enabled; hover details keep the Nook open. Weather uses Open-Meteo and
an IP location fallback. Lyrics use their provider, and updates use GitHub.
Only the Battery widget starts Bluetooth monitoring. There are no Bluetooth
connection or device-battery live activities; power feedback precedes routine
system-control feedback, and the host window tracks live activity size. System
feedback covers only microphone mute and Focus: volume and brightness are left
to macOS's own indicators. Home widget tiles have no header (icon or name):
their content identifies them, and VoiceOver names the tile. The Media widget
mirrors the Music page (artwork wash, slim scrubber) without lyrics: lyrics show only
on the Music page, and only load and advance while it's visible. The lyrics bar under
Home was removed in 2.63 (the Music page replaces it). Clicking a tile selects it (accent outline); Delete or Forward Delete removes it, ⌘Z or the Undo bar restores it in
place for six seconds, and Escape deselects. Keys pass through while a text field
has focus. Animated views use timer-scheduled TimelineViews, not `.animation`
schedules, which pause when macOS reports the menu-bar panel as hidden.
Bluetooth uses paired-device reads plus the macOS connected-device report when
IOBluetooth omits accessories. Battery reads are cached for 30 seconds; connection
fallback refreshes every four seconds. Unknown values stay unknown, and earbud
and case levels remain separate. Power uses the internal battery's capacity ratio
and charging flag, not the presence of external power.
2.54 additions: `MeetingCountdown` (closed-notch countdown for video meetings from
10 min before to 5 min after start; demands the events service only when Calendar
access is already granted; NookSettings.showMeetingLiveActivity). `AgentActivityMonitor`
(Settings → Activities → Coding agents, off by default): installs a silent hook
(`activity-hook.sh`, events UserPromptSubmit/PostToolUse/Notification/Stop/SessionEnd via
`AgentHookConfig.merged(events:)`) that writes per-session status files; the closed
notch shows needs-you, working (count) or done (8 s). `AudioOutputs` (CoreAudio default
output; menu on the Music page). Tray/basket AirDrop buttons (`airDropAll`).
`NookSettings.hiddenInApps`: NotchManager orders the windows out while one of those
apps is frontmost. Widgets `.devServers` (`DevServers`: lsof LISTEN sockets for the
user's own processes, excluding macOS services and app bundles except Xcode's
developer tools; cwd via proc_pidinfo; Open/Stop with SIGTERM) and `.calculator`
(`Calculator`: recursive-descent arithmetic, Foundation units, ECB currencies via
frankfurter.app on demand; Scripts/check-calculator.sh). MACSPACES_QA_SCOPE=tools-254.
2.55 additions: Teleprompter page (`ScriptPrompter`, scripts in Application Support/
scripts.json; `PrompterPanel` under the notch with `sharingType = .none`; scroll at wpm
or follow the voice via `VoiceFollower` (SFSpeechRecognizer on-device, mic/speech
asked only in voice mode) and the pure `ScriptAligner` (Scripts/check-prompter.sh)).
`ScreenshotWatcher` (off by default; NSMetadataQuery for kMDItemIsScreenCapture or
screenshot-named images created since start, since macOS 27 doesn't set the flag)
adds new screenshots to the Tray with a closed-notch thumbnail; Tray images have Copy
Text (Vision). `NotchBanners`: cards under the notch (hidden from capture and while
locked) for new Messages (attributedBody decoded by `TypedStreamText`, no
unarchiving) and, opt-in, other apps' notifications (`SystemNotificationsReader` on
usernoted's db2 store, read-only, Full Disk Access; fails closed). The Messages widget
is no longer "developing"; incoming Messages keeps its service running. Credential filter adds Luhn card
numbers and `.env` secret blocks. Converter wheel segments have soft corners and one
choice draws a whole ring. Settings can grow but not shrink below 980×680.
MACSPACES_QA_SCOPE=release-255 and wheel.
2.56 additions: clipboard entries carry `recognizedText` (Vision OCR on image clips, off
the main thread) and search covers it; `ClipboardQuery` parses `@kind`, `@app`, `#collection`;
snippets (`addSnippet`, source "Snippet", pinned) and collections (`tags`, filing pins
a clip); `removeUnused(olderThan:)` with ClipboardPreferences.autoDeleteDays; pins and
snippets saved to clipboard-pins.json (0600) when `keepsPins` (default on); `ClipMenu`
(copy as case styles, pin, collection, delete) shared by popup and page; pin keys ⌃A…
(no N, P, U); drag out via `ClipboardActions.dragItem`; NSColorSampler colour picking;
`MaccyImport` reads Maccy's Storage.sqlite (ZHISTORYITEM/ZHISTORYITEMCONTENT) read-only,
credential-filtered (fixture in check-clipboard). Timers: up to three `TimerService`
slots (keys timer, timer2, timer3; `timers.count`), the original card style; Focus left
the Timers page (the Focus timer widget remains; NamedTimers from 2.55 is gone). 2.57: cards
have no header, the page is 236 pt tall, and the closed notch lists every running
timer (`NotchViewModel.timerLabel`), widening its lane to fit. Output
menu lists paired Bluetooth audio devices (only once Bluetooth access exists) and
connects them. Converter: PDF→TXT removed; image tool "Under 1 MB" (`underOneMegabyte`).
2.57: the Terminal page is `TerminalPage` (shell + `CodingPanel`). `CodingStats` reads
~/.claude/projects/**/*.jsonl (assistant usage, deduplicated by message id + request id)
and ~/.codex/sessions/**/*.jsonl (token_count `last_token_usage`, latest `rate_limits`
primary/secondary) modified in the last 14 days, incrementally by byte offset (only
complete new lines), every 30 s while the page shows. GitHub contributions come from
the public calendar (no token) for `coding.githubUser`, defaulting to gh's hosts.yml
user, at most hourly. MACSPACES_QA_SCOPE=coding renders synthetic numbers.
2.58: lyric styles are six (Classic, Poster, Choreography, Stickers, Karaoke, Typewriter;
always a whole number of rows of three). Stickers = Poster + `LyricSticker` (one general
word list → SF Symbol drawn and moved from time in a TimelineView; broken heart splits
the symbol in halves). Karaoke reads `TeleprompterService.lineProgress` (timed lyrics).
The Lyrics card is a collapsed drawer like the theme drawers. Focus timer: a moon
button (`PomodoroModel.silencesDuringFocus`) runs the Shortcuts "MacSpaces Focus On/Off"
(found by name; one-time guided setup). Settings fills the title bar (content scrolls
under a fade; sidebar and divider run to the top). The Terminal page's coding column
uses tabs (Today, Usage, GitHub, Servers) instead of scrolling.
2.59 (restructure, its own release so it can be rolled back to v2.58): Home widgets
and dock pages are one feature at different sizes. `NookWidgetKind.page` names the page
behind each widget (nil for Clock, Calculator, Messages); a tile's corner button,
double-click or "Open …" menu item calls `NotchViewModel.openPage(for:from:)`, which
records `pageAnchor` (the tile's centre in the page area) so the page scales out of the
tile (`.id(selectedTab)` + asymmetric transition in NotchContainerView). Shared pieces
live once: `ClipListRow` (Clipboard widget and page) and `ClipMenu` (popup, page, widget).
Next steps, in order: share Calendar/Reminders rows, make each page the feature at page
size, then merge `NotchTab` into the feature catalog with a saved-dock migration.
2.60: `SecureStorage` seals saved clipboard history, clipboard-pins.json and scripts.json
with AES-GCM ("MSE1" header); the key is HKDF from a CryptoKit Secure Enclave P-256
key agreement (device-bound blob + peer public key in storage-key.json, 0600), or a
keychain generic-password key without an enclave; plaintext files from earlier versions
are read and re-sealed (QA scope secure-storage exercises the real enclave). Stickers
are scenes (Emitter particles, Ripples, ClockFace, BrokenHeart: symbol cut along a
jagged crack that draws in, halves part, shards fall); QA scope stickers renders
filmstrips. The Terminal page is one tab bar (Shell, Today, Usage, GitHub, Servers),
full width; the terminal view stays mounted (hidden) while other tabs show.
2.61: each timer slot has its own colour (`TimerService.tint`: orange, cyan, pink), on its
card ring and for its time in the closed notch (`NotchViewModel.runningTimers`). Stickers sit
beside the poster with their whole frame reserved, never over the headline.
2.62: the timer lane is measured in the rounded font it draws with; times never wrap.
2.63: a fresh install starts with Home = Music (large), Timer, Clock and the dock Music, Weather,
Calendar, System, Terminal, Tray, Timers, Mirror (`NotchTab.defaultDock`, also Reset); installs
with saved profiles but no saved dock keep `NotchTab.legacyDock`. Settings → Widgets → Dock
reorders shown pages by dragging the ☰ handle (`DockAppsCard`, `NookSettings.moveDockApp(_:to:)`;
QA scope dock-settings).
2.64: 47 stickers; `symbol()` gives each depth (gradient, highlight, shadow); the world is
`Globe` (a projected sphere). Avoid rotation3DEffect spins (they vanish edge-on in captures and
look flat); scale x instead. The Settings sidebar marks the selection with its highlight only.
2.65: 92 stickers, every one in `LyricSticker.color` (natural colours, never the accent; the
switch is exhaustive so a new sticker must pick one) and fitted in a square. `match` prefers the
headline word, then concrete words, then `weakWords`. Lyrics match across scripts
(`TeleprompterService.latin`/`similar`, title-only search stage) and blanked words are restored
from lyrics.ovh (`uncensor`); MacSpaces itself never censors.
2.66: the agent hook (also PreToolUse) keeps the first KB of the prompt, tool and notification
payloads beside each status file, a byte per step, and the host app (`__CFBundleIdentifier`,
`TERM_PROGRAM`); `AgentHookConfig.describe` turns a tool call into "Editing X" / "Running Y".
Enabled installs are upgraded on launch. The closed notch shows the host app's icon and the
action; the Terminal page has an Agents tab (click a row to activate its app). Power is a gauge
and a percentage at the standard lane width.
2.67: Messages handles get names from Contacts (`ContactNames`; asked only once incoming Messages
is on and a message arrives). The GitHub tab parses daily counts from the calendar tooltips and
shows streaks, week, best day and months; Usage ranks projects and models.
2.68: World Clock widget (`.worldClock`, `WorldClockWidget`/`DotFont`, cities in
`WidgetOptions.worldClockCities`; QA scope world-clock). The closed notch shows no agent text: the app
icon in an animated ring and a matching pulse, at the standard width; details are in the Agents tab.
2.69: Messages page (`.messages`, `MessagesPage`): `MessageInboxReader` reads recent chats and the
open thread read-only while the page shows, nothing kept; replies (page and the banner's inline
field) use `quickReply(_:toChat:)`, which sends only to the exact chat id verified through Messages
scripting. A needs-you agent posts a persistent card with Go. MacSpaces does not answer agents'
permission prompts.
2.70: one Clock widget with Style (Regular/Dot, `DotClock`) and Places (`clockPlaces`); saved
`worldClock` tiles become a Dot clock. The Add Widgets sheet groups come from
`NookWidgetKind.libraryGroups`, which must list every widget (checked). The agent pulse is the
vendored ThinkingOrbs orb (MIT; Sources/Vendor, excluded README/LICENSE from the bundle, credited
in Acknowledgements) on a periodic timeline; Claude orange, Codex pale blue.
2.71: stickers are chosen by vote across the line's words, then by on-device word meaning
(`NLEmbedding`, strict 0.88 cutoff). The agent notch is the app icon (no ring) and the
`.searching` orb.
2.72: themes regrouped (see Appearance below); Messages show Contacts photos (`ContactNames.photo`).
2.73: the Messages thread folds reactions onto their message and shows attachments (images
inline). Conversations can be hidden locally or deleted through Messages' own confirmation;
MacSpaces never writes chat.db and never confirms a delete itself.
2.74: the agent orb uses ThinkingOrbs' 64 px preset at 22 pt (three passes through its mask); the
20 px preset scatters into specks on a Retina notch.
2.75: Settings → Activities → Clipboard & Tray turns off the closed notch's paste-queue count
(`NookSettings.showPasteQueueLiveActivity`) and new-screenshot card (`showScreenshotLiveActivity`);
the queue and screenshot watcher keep working. QA scope activities renders the page.
2.76 (2.75 audit fixes): Messages drafts are kept per chat (`ChatDrafts`) and a send takes the
chat and its draft together; the inbox counts page consumers per display and rejects late reads
(`InboxSession`, Sources/Core/Messaging). Saved files that exist but can't be read (scripts.json,
clipboard-pins.json) are never overwritten or removed (`ProtectedFile`); Start New Library or Clear
All renames them aside. Voice following refuses to start without on-device recognition
(`OnDeviceSpeech`) and scrolls instead. Maccy imports apply ignored apps and private/ignored types.
Focus Off follows what MacSpaces turned on (`FocusSilencing`). Codex usage counts a cumulative
total once, and coding rankings keep only entries from the last 14 days (Scripts/check-coding.sh).
The hidden-in-apps rule is applied when windows are built (`HiddenApps`).
2.77: closed-notch lanes fit their content: each side is drawn at its natural width plus padding
and measured (`LaneWidthKey` → `NotchViewModel.measuredLaneContent`); both lanes take the wider
side (minimum 36 pt) and the narrower side sits toward the outer edge. 2.78: 10 pt padding on the
outer (corner) side and 4 pt beside the camera. Power and system cards keep
their fixed lanes. QA scope coding renders agent-notch-closed.png.
Website/README captures (Debug only): MACSPACES_DEMO_KIND=notch with MACSPACES_DEMO_THEME=everforest; clips
MACSPACES_DEMO_CLIPS=theme-*, page-* (each tool page in its own theme) and wallpaper-lava; FeatureQA scope
site-green (clipboard popup, Messages, coding, Tray in Everforest); site-converter with MACSPACES_CONVERTER_BG=white|black
(a pair gives real alpha). Set MACSPACES_VISUAL_QA=1 so a second demo instance isn't stopped by the duplicate guard.
Covers come from /private/tmp/macspaces-covers (never committed). Shortcuts and timers have Debug-only previews
(`ShortcutsService.setPreview`, `TimerService.setPreview`); the real Shortcuts list is never read in captures.
2.79: the converter wheel's centre is a file (`FileGlyph`: a page with the extension, stacked for
several), not a QuickLook thumbnail of its contents; the wheel no longer generates thumbnails
(`ConverterWheel.preview(_:tools:hovered:)`). QA scope site-themes renders every theme drawer open.
2.80: notifications open their page instead of a card when it's in the dock (`NotchBanners.page(for:dock:)`):
Messages → the Messages page on that chat, agents → the Terminal page's Agents tab, via `NotchManager.active.present`
(`NotchViewModel.present(_:for:)`, closes after `showsFor` unless hovered; refused while the Nook is in use, then a
card). Cards are as tall as their content (`fittedSize()`). Notarization waits up to 60 minutes.
Camera access belongs only to the optional Mirror. Never request permissions for
unused features or use real camera/clipboard content in promotional captures.

## Build and release

Swift 5.9; macOS 15 deployment target, universal (arm64 and x86_64); Xcode and XcodeGen. `project.yml` is the
canonical project definition. The generated Xcode project is ignored.
The one package dependency is SwiftTerm (MIT, pinned exactly in project.yml) for
the Terminal widget. Its build-tool plugin means every `xcodebuild` passes
`-skipPackagePluginValidation` (Makefile, CI and package-release.sh do); its
licence ships in Sources/Resources/Acknowledgements.txt.

Bundle: `dev.opensource.MacSpaces`. Team: `28LJG7MXT3`. Versions are in project.yml.
Keep the bundle identifier stable to preserve settings and update verification.

`make` builds locally. `make release` runs Scripts/package-release.sh: universal Release build, Developer ID signature with hardened runtime, app
notarization, stapling, DMG creation, DMG notarization and stapling, then mounted
app signature, architecture and Gatekeeper verification. Keychain profile:
`MacSpaces`. Never commit credentials, generated projects or release artifacts.

### Release policy

`main` holds one commit per major version: the root `MacSpaces 1.14` and
`MacSpaces 2.80` on top of it. Each has its own README. Public releases use
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
  build. Push the release commit, then run `make release` while CI runs on it
  (CI runs checks and the Release build as parallel jobs). Only once CI passes on
  that exact commit, push the `vX.Y` tag there and run `Scripts/publish-release.sh`,
  which creates or updates that version's release. Notarization stays two rounds
  (app, then disk image) so both are stapled and the app passes Gatekeeper offline.
- `RELEASE_NOTES.md` describes the current version and names it in bold. The
  publisher adds one hidden `macspaces-build` marker for update detection.

Stable (1.x) installs read releases/latest. Pre-release (2.x) installs read the
release list and take the newest non-draft release with their own major version
(`ReleaseRevision.newest`), so they never receive 1.x or a future 3.x; they
download automatically by default. Both take the public version from the tag,
compare internal build numbers, check hourly (at most every six hours) while
running, and verify the downloaded app's version, build, bundle identifier,
signing-team identity, minimum macOS and architecture before asking to relaunch.
A build this Mac can't run is remembered and not downloaded again. QA and demo bundles never update. Replacement installers use
increasing internal builds. 2.x is the latest (official) release, so 1.14
installs are offered it. 1.14's updater cannot check the minimum macOS, so on
macOS 13 and 14 it would install an app that needs macOS 15. 2.x releases are published by hand
with Scripts/publish-release.sh (Latest, not pre-release), which refuses
development builds.
Homebrew: `zlichtman/tap/macspaces` is the only MacSpaces cask (the current 2.x);
`macspaces@1` and `macspaces@beta` were retired, and the tap's cask_renames.json
moves beta installs to `macspaces`.

CI builds Release on macos-26. A passing local build is insufficient: check the
GitHub build on the commit being released. Use explicit captures in nested actor
closures for compatibility with the CI compiler.

## Demo and regression checks

Build Debug with PRODUCT_BUNDLE_IDENTIFIER=dev.opensource.MacSpaces.WebsiteDemo.
Launch with MACSPACES_WEBSITE_DEMO=1 and optionally MACSPACES_DEMO_OUTPUT;
MACSPACES_DEMO_KIND=2.x, notch or home picks the 2.x video, the notch video or the website Home still.
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

Appearance uses ThemeFamily for paired light/dark palettes and AppearanceMode for System/Light/Dark. Themes are grouped into drawers (`ThemeCollection`), each a multiple of five (checked): Core (exactly the five app themes MacSpaces, PowderMeet, Heartable, KemoSabe and Tsukumo, in that order), Terminal (classic editor palettes, Karma and the single-colour themes, with Custom always last), then six groups of scenes: Bloom, Forest, Earth, Water, Sky and Tech (2.72; Nature and Live are gone and are never named in the UI). Every scene theme has exactly one effect (checked). Outside Core, drawers are ordered by colour (`ThemeCollection.byColour`: greys, then hue from red to pink); don't label that ordering. Every family belongs to exactly one drawer; Settings shows them as collapsible drawers and the Nook menu as submenus. Never use a brand's name, logo or wording for a theme. Retired themes map to replacements in `ThemeFamily.replaced` (One Dark → Karma; 2.38's Sweets and Studio themes; Pulse → Fireworks in 2.47; 2.72's Dracula, Tomorrow Night, Kanagawa, Night Owl, Fireworks, Coral and Sandbar). `ThemeFamily.motif` gives a theme an effect (ThemeMotif: original geometry drawn in code, faded toward the center) behind the open Nook and on its Settings card. Effects animate at up to 30 fps only while the Nook is open, never under Reduce Motion, and hold a still frame on cards; `ThemeStore.showsPatterns` and `animatesEffects` turn them off. Custom is a user-chosen background and accent (CustomThemeColors; text is pure white or black for contrast). Preview images contain no appearance or variant labels. Settings and the Nook menu use the same catalog. ThemePreset remains a compatibility catalog: do not remove saved IDs or overwrite custom colors. App icons are independent of appearance. The app icon is `Sources/Resources/AppIcon.icon` (Icon Composer; black image layer under the slashes, since macOS 26 lightens a solid fill); Xcode derives the rounded macOS 15 icon from it. Scripts/generate-app-icon.swift writes its layers. Run Scripts/check-appearance.sh for migration and contrast checks.
