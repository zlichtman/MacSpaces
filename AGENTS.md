# MacSpaces engineering guide

MacSpaces is a native macOS menu-bar app built around the **Nook**: a panel that opens from the physical camera notch, or a synthetic notch on other displays, with a dock of full pages, a Home grid of widgets, a file Tray, compact live activities beside the closed notch and cards under it.

- The version and build live in `project.yml` (and `RELEASE_NOTES.md`); don't repeat them here.
- `README.md` is the public page, `CHANGELOG.md` is the history (one entry per version), `Demos/README.md` describes the README images. This guide is the current state only: when something changes, edit the relevant section in the present tense and add history to the changelog, never a "X.Y:" paragraph here.

## Code layout

- `Sources/Core`: pure catalogs and logic: feature catalog and dependency-aware service lifecycle (`Features`), action registry (`Actions`), `CompletedFileTracker` (`Files`), playback capabilities (`Media`), `InboxSession`/reply state (`Messaging`), `NoteRepository`. `FeatureCatalog` keeps only shipped features and the fields `NookWidgetKind` reads (title, symbol, summary, permissions, width, compact).
- `Sources/App`: entry, menu-bar menu, `AppServices` (service demand), `ModuleCoordinator` (creates only `NotchManager`), updates.
- `Sources/Modules/Notch`: `Core` (display geometry, per-display windows, hover, collapse/expand, sizing), `UI` (panel shape, dock, live activities, transitions), `Features/Widgets` (Home dashboard and widget views), `Settings` (`NookSettings`, `WidgetOptions`, the General/Notch/Files panes).
- `Sources/Modules/{Actions, Clipboard, Converter, Meetings, Prompter, Voice}`: Find Action, App Intents and Finder Services; the clipboard popup; File Converter and File Tools; meeting controls; teleprompter; dictation.
- `Sources/Services`: media, lyrics, weather, calendar, clipboard, timers, coding stats, updates and other services. `PowerHelperProtocol.swift` is shared with the helper.
- `Sources/DesignSystem`: themes, `Design` motion tokens (open/close/hover springs, `nookDepth` transitions), optional trackpad `Haptics`, `OlderMacOS.swift` stand-ins, `RefreshButton` (its arrow turns once per click). All motion honours Reduce Motion (system or the app's own).
- `Sources/Settings`: the Settings window, search index, Home layout editor and inline sample widget gallery, Clipboard preferences.
- `Sources/Debug`: Debug-only QA harnesses, regression checks and website capture.
- `Helpers/PowerHelper`: the privileged helper. `Tests/`: sources for `Scripts/check-*.sh`.
- Shared keys: `WidgetOptions.Keys` (no repeated key strings).

## Compatibility

- Swift 5.9; macOS 13 deployment target; universal (arm64 and x86_64). `project.yml` is the project definition (XcodeGen); the generated Xcode project is ignored. iCloud conflict copies `Sources/Resources/Info *.plist` are ignored by Git and excluded from the project.
- Anything newer than macOS 13 needs `#available` with a fallback. Shared stand-ins live in `OlderMacOS.swift` (`refreshTurn`, `scrollContentTopMargin`, `textFieldKeys`, `NoSearchResultsView`); `onChange` uses the one-value form; EventKit `.fullAccess` is checked with `#available` (`.authorized` before 14).
- Before macOS 14 the Settings search and Terminal bar handle Escape but not ↑/↓, and the refresh arrow uses a plain rotation. Before macOS 15 notification banners read `$DARWIN_USER_DIR/com.apple.notificationcenter/db2/db`.
- macOS 14+-only features (listed in README Requirements): Tray Remove Background, Continuity Camera/Desk View in Mirror, ↑/↓ in Settings search and the Terminal bar.
- Use explicit captures in nested actor closures (the CI compiler requires it). Locks used from async code are `OSAllocatedUnfairLock`, not `NSLock`.
- Animated views use timer-scheduled (`.periodic`) TimelineViews, not `.animation` schedules, which pause when macOS reports the menu-bar panel as hidden. Avoid `rotation3DEffect` spins (they vanish edge-on and look flat); scale x instead.
- Timers schedule in `.common` run-loop modes so they move while a menu is open.

## Nook shell

- **Geometry**: app pages share a 620×346 base, clamped to the display; Home follows its widgets (legacy manual sizing preferences are kept but don't control geometry). Content starts below the physical camera; a detached dock sits below the panel and the shared hover region includes the gap. AppKit owns window geometry (SwiftUI size propagation is isolated).
- **Opening**: click always opens; hover, scroll-down and file drags are optional (General → Open & close). File drags open Tray only after pausing near the closed notch. Hover and scroll open only with the pointer on the closed notch itself (`NotchViewModel.isPointerOnClosedNotch`, the notch plus its hover peek); SwiftUI can report hover where the open panel was while it closes, so a hover that starts elsewhere waits for the pointer to reach the notch. Hover and scroll never open the Nook while Mission Control or App Exposé shows (`MissionControl.isActive`), and an open Nook checks about three times a second and closes when Mission Control appears.
- **Performance**: `MissionControl.isActive()` coalesces background WindowServer queries; hover/scroll requests validate their request ID after awaiting. `MotifImages` retains the selected scene, decoded off-main. Decorative motion waits for opening. Closed-lane observations stay in `CollapsedNotchContent`; only settings/lane geometry can resize the host. Statistics, agent scans and Tray metadata run on bounded workers, publishing only current results. `ArtworkWashStore` prepares washes off-main with one reusable Core Image context. The shell's surface tint is a plain gradient under the panel's clip (a gradient-filled animating shape was redrawn by Core Graphics every frame). The microphone/Focus monitor reads CoreAudio and Focus on a utility queue. The scrubber is its own small view on a quarter-second timeline.
- **Hide in apps** (`NookSettings.hiddenInApps`, General): windows are ordered out while one of those apps is frontmost, and the rule is applied when windows are built (`HiddenApps`).
- **Keyboard**: a closed Nook hands the keyboard back (`NotchManager` reorders a key `NotchWindow` on collapse). Widget keys (Delete, ⌘Z, Escape) are ignored while any text input has focus. Keyboard-opened pages stay open until closed.
- **Dock**, three capsules; long lists scroll inside their capsule:
  - App pages (`NookSettings.dockApps`, chosen and reordered in Settings → Notch → Apps by the ☰ handle, `DockAppsCard`), Home always last. File drops open Tray even when it isn't in the dock.
  - Controls for the active page: on Home one button per profile (`NookProfile.symbol`, shown only with two or more profiles); on Music the playlist (playlist order), only while Apple Music is the source; other players leave no empty capsule.
  - Settings, with optional Pin and Close (`showDockPin`/`showDockClose`, default and reset on).
  - Fresh install and Reset: `NotchTab.defaultDock` (Music, Weather, Calendar, Clock, System, Terminal, Tray, Timers, Mirror, Meetings, Dictation). Installs with saved profiles but no saved dock keep `NotchTab.legacyDock`. Meetings/Dictation and Clock were appended once to saved docks (`dock.communicationPagesAdded`, `dock.clockPageAdded`); later removal persists. Saved docks drop retired pages on decode.
- **Home**:
  - `NookWidgetKind` is the widget catalog; its cases drive the library, persistence and view factory, and new cases need a title, symbol and sizing. Menus list widgets alphabetically (`NookWidgetKind.alphabetical`); Add Widgets groups come from `NookWidgetKind.libraryGroups`, which must list every widget. Saved profiles drop removed widgets and style fields on decode.
  - Fresh Home (profile “Home”): Music (large), Timer, regular Clock (`starterWidgets`, `starterSizes`).
  - Each widget uses one canonical size (`defaultSize`); legacy saved size fields decode but do not control layout. Music is large; Clock, timers, Battery and Keep Awake are compact. Adjacent compact widgets stack, oversized profiles scroll, and the empty profile opens the visual gallery. Tiles have no header (VoiceOver names them).
  - Clicking selects (accent outline); Delete/Forward Delete removes; ⌘Z or the Undo bar restores in place for six seconds; Escape deselects.
- **Widgets and pages are one feature at two sizes**: `NookWidgetKind.page` names the page behind a widget (nil for Calculator); the tile's corner button, double-click or "Open …" calls `NotchViewModel.openPage(for:from:)`, which records `pageAnchor` so the page scales out of the tile. Shared pieces live once (`ClipListRow`, `ClipMenu`).
  - Open work: share Calendar/Reminders rows, make each page the feature at page size, then merge `NotchTab` into the feature catalog with a saved-dock migration.
- **Mirror**: one shared camera controller retains one session and serial worker queue across visits and displays. Device discovery/configuration stay off-main and discovery is cached for 30 seconds or until a device change. Opening the Nook can preconfigure an already-authorized camera when Mirror is in the dock; capture starts only with a visible Mirror. Readiness waits for a video frame, interruptions and runtime failures recover or offer retry, and outgoing previews detach synchronously before panel/page transitions. Preview layer updates disable implicit animations. Camera permission remains an explicit button action. The chosen camera (`preferredCameraID`, `mirror.selectedCameraID`) is kept while it's unplugged: Mirror skips disconnected devices, replaces a dead input, falls back to the built-in camera first, looks again 1.2 s after a device change, and returns to the chosen camera when it's back.
- **Service demand** follows enabled widgets and visible pages; a closed page's services keep running four seconds (`lingeringTabs`); safe dock services warm during hover and while open, Music takes a passive system metadata snapshot without AppleScript, page startup reconciles on the next run-loop turn, and stopped work rejects late generations.
- **Closed notch** (live activities): music bars, every running timer in its colour, the meeting countdown, power, paste-queue count, new-screenshot thumbnail, microphone mute and Focus, each toggled on Settings → Activities → Beside the notch.
  - Lanes fit their content (`LaneWidthKey` → `NotchViewModel.measuredLaneContent`): both lanes take the wider side (minimum 36 pt) with 10 pt on the outer side and 4 pt beside the camera; power and system cards keep fixed lanes. Power feedback precedes routine system-control feedback.
- **Notifications under the notch** (`NotchBanners`, routed by the pure `NotificationRoute`): a new message opens the Messages page on its conversation and an agent that needs you opens the Terminal page's Agents tab with that session outlined (`AgentActivityMonitor.spotlight`), whether or not the page is in the dock (`NotchManager.present` → `NotchViewModel.present`, closes after `showsFor` unless the pointer moves in). The first click into a Nook opened by a message focuses that conversation's reply field (`MessagesReplyService.replyFocusChat`); it never takes the keyboard on its own. A notification never takes a Nook in use (`isInUse`); then, or with Settings → Activities → Under the notch set to Show a card (`banners.delivery`), a card shows, and clicking it opens the same place (even in a Nook in use), falling back to Messages or the agent's app without a Nook. Other apps' notifications are always cards that open their page (`NotificationRoute.page(forApp:)`: Messages, Calendar, Reminders, Notes, Weather, Music, Clock) or the app. A Nook a notification opened is hidden from screen sharing and recordings until it closes, like the cards. While locked or a Hide in app is in front nothing shows: an agent's card waits and returns on unlock or when that app leaves, the rest are dropped. Cards are as tall as their content (`fittedSize()`).
- **Menu-bar menu**: Open Nook, Find Action (with its hot key), Enable Nook, File Converter ▸ (Convert by Shift-Dragging, Open File Tools), File Baskets │ Settings │ Check for Updates │ Quit MacSpaces. No ellipses.
- **Find Action** (`ActionSearchWindow`, default ⌃⌥Space, set in General → Keyboard) searches MacSpaces actions and Apple Shortcuts, not apps or files. Optional direct page shortcuts (⌃⌥N Home, T Tray, M Music, K Terminal, D Dictation).
- **App Intents** (`MacSpacesIntents.swift`): open a Nook page, stage files in the Tray, convert files and return the results. **Finder Services** (`project.yml` NSServices): Add to MacSpaces Tray, MacSpaces File Tools.

## Settings

- Pages, in order (`SettingsDestination`), under three non-collapsing sidebar labels (`SettingsDestination.section`); there is no About page:
  - **Core** section:
    - **General**: updates with the version first, then startup, displays, open & close, keyboard, hide in apps and reset.
    - **Appearance**: theme drawers (closed on entry), Lyrics, Motion.
    - **Permissions** (`WidgetAccessSettings`): each permission's live status, re-read every 2 s while open; opening it requests nothing, and a row's Allow… or Open Settings button asks or opens System Settings.
  - **Notch** section:
    - **Home** (case `widgets`, `NookSettingsPane`): compact profiles, visual layout with inline removal and drag reordering, and an inline widget gallery. Gallery previews use sample content and start no services; the starter previews share the real Music, Clock and Timer components, and each gallery row fills its width. Typed `dev.opensource.MacSpaces.widget` drops add into the layout or native Nook; a drag temporarily pins Home, restored on finish/cancel. Selecting a layout preview gives it keyboard focus: Delete/Forward Delete removes it and Escape deselects; keys in text fields keep editing text.
    - **Apps** (case `apps`): the Dock card; page-specific controls stay on their pages (`DockAppsCard`); unused pages are alphabetical.
    - **Activities** (case `activities`, `ActivitiesSettingsPane`): Beside the notch, Under the notch (including Coding agents that need you and the Open its page / Show a card choice).
  - **Tools** section:
    - **Files**: Screenshots, Downloads & folders, File Converter.
    - **Clipboard**, including Keep history after quitting.
- `SettingsSearch.entries` indexes every card (⌘F); add an entry for each new card. Settings remember the current destination, and Nook shortcuts open the relevant page.
- The window can grow but not shrink below 980×680 (less only on a short screen); tiling that squashes it is undone. Content scrolls under the title bar with a fade; the sidebar marks the selection with its highlight only.
- Settings shows only the version (the build appears on hover).

## Features by area

### Music and lyrics
- Lyrics show only on the Music page and advance only while it's visible; lookups may start while the Nook opens (`TeleprompterService.prefetch`, from `AppServices.prewarmDockPages` with Music in the dock and the player already being read). The Media widget mirrors the page (slim scrubber, no artwork wash) without lyrics.
- `LyricStyle` (Settings → Appearance → Lyrics, previews in the theme's colours): Classic, Poster, Choreography, Stickers, Karaoke, Typewriter (always whole rows of three). Poster is the default. All six styles remain available. Styles use only the theme's accent and ink; motion stops under Reduce Motion (system or the app's own). Retired styles read back as Classic.
  - Every line change, a repeated line included, has its own `TeleprompterService.lineID`; styles key their entrance on it. The shared handover is a 0.18 s fade.
  - Poster sets the longest word (filler such as "something" excepted) as a condensed headline; supporting text keeps a readable floor (11–13 pt). Each line keeps its own composition (`PosterLyric.composition(for:)`): mostly left-aligned, flush right only for short lines. Short tails sit beside the headline at its natural width; longer phrases stack below.
  - Stickers = Poster + `LyricSticker`, beside the headline with its whole frame reserved. Each sticker is drawn in code with depth (gradient, highlight, shadow) and colours from `LyricSticker.color` (natural colours, never the accent; the switch is exhaustive, so a new sticker must pick one), fitted in a square, keyed by sticker so the same one carries on across lines. Choice: a vote across the line's distinct words (strong 2, weak 1, +2 for a strong headline) that needs at least 2 (one common word alone draws nothing), then on-device meaning (`NLEmbedding`, 0.88 cutoff). A broken heart needs "heart" and a break word within three words.
  - Karaoke fills letter by letter (so wrapped lines fill in reading order) over the line's sung span from `LyricTimeline` (the last line to the song's end); untimed lyrics show filled. Typewriter types within the first 60% of the line (at most 1.1 s) from the song's clock, with the whole line laid out. Both run one 30 fps timeline only while playing.
- Lookup (`TeleprompterService`, pure logic in `Sources/Core/Media/Lyrics.swift`): LRCLIB's exact `/api/get` (title, artist, album, length), then searches by title and artist, free text and title alone. Matches must agree on title and artist (edition suffixes and features ignored, across scripts via `latin`/`similar`); timed lyrics from another cut lose to the right length. Records with missing/null duration are accepted and malformed ones skipped individually. A busy or failing LRCLIB (503, 429, timeout) is asked again 1.5, 3, 6 and 12 s later; lyrics.ovh's plain text stands in only after two tries, and is the answer only when LRCLIB has no match. Intros and blank LRC lines clear the lyric; `[offset:]` applies. Blanked words are restored from lyrics.ovh (`uncensor`).
- `LyricsCache` (Caches/…/lyrics.json, 500 songs, written off-main): timed lyrics stay, plain lyrics are looked up again after a week and "none found" after a day; failures are never stored.
- One clock: `NowPlayingController.estimatedElapsed` drives lyrics and the scrubber. A reading that agrees with the estimate within 0.3 s changes nothing (`NowPlayingClock.agrees`), so the clock never jitters and observers redraw only on real changes. MediaRemote's elapsed time is as of its timestamp; AppleScript readings are timed inside the runner. `LyricTimeline` sets one timer for the next change: sung lines show `LyricTimeline.lead` (0.25 s) early, rests and caption ends exactly on time.
- Reading the player: polling scripts are compiled once (`AppleScriptRunner.runSynchronously(_:reuse:)`). `NowPlayingClock.pollInterval`: 1 s while a position view shows and a song plays, 2.5 s playing otherwise, 4 s paused, 0.3 s for the first 3 s of a song without a cover. Spotify's and Music's change notifications refresh at once. MediaRemote, which answers nothing to apps outside Apple's list on macOS 15.4+, is skipped for 30 s after a script found a track it missed.
- Covers: `SpotifyCovers` listens for Spotify's PlaybackStateChanged notification, refreshes at once and fetches the oEmbed cover (300 px, then 640 px). If no cover arrives, `ArtworkLookup` waits 1.2 s and searches iTunes then Deezer once per track, accepting only a normalised artist + album/title match (cached; misses remembered; real app only). `HeldArtwork` keeps the previous cover (and the wash) up to 1.5 s while the next loads, then crossfades.
- With nothing playing the Music page shows one centred invitation with a button per installed player (Spotify, Music) that opens it.
- Apple Music's dock control shows playlist order, not private Up Next. Spotify's local integration exposes no queue; other players have no Music dock controls.

### Terminal and coding
- Terminal widget (`.terminal`, medium/large) and page: one login shell (`QuickShell`, SwiftTerm) that keeps running when the Nook closes and stops when the widget leaves Home; only the most recently shown host holds the terminal view. Return sends the bar's command; swipe up or ↑ steps through history (`terminal.history`, clearable). Clicking the output gives it the keyboard for prompts. The Nook stays open while the bar holds unsent text.
- `TerminalPage` tabs: Shell, Agents, Today, Usage, GitHub, Servers (`CodingPanel.Tab`); the terminal stays mounted while other tabs show.
- `CodingStats` reads `~/.claude/projects/**/*.jsonl` (assistant usage, deduplicated by message + request id) and `~/.codex/sessions/**/*.jsonl` (`last_token_usage`, latest `rate_limits`; a cumulative total counts once) modified in the last 14 days, incrementally by byte offset, every 30 s while the page shows. Projects are named by repository (`projectName`: strips `.claude/worktrees/…` and Orca workspaces, nearest `.git`); `<synthetic>` is skipped.
- GitHub tab: the public contribution calendar (no token) for `coding.githubUser` (default: gh's hosts.yml user), at most hourly; counts from the calendar tooltips.
- Agents (`AgentActivityMonitor`, Settings → Activities → Coding agents that need you, off by default; one that needs you opens the Agents tab on it):
  - One silent hook (`activity-hook.sh`; events UserPromptSubmit, PreToolUse, PostToolUse, Notification, Stop, SessionEnd via `AgentHookConfig.merged(events:)`) in `~/.claude/settings.json` and `~/.codex/hooks.json`, keeping the user's hooks.
  - It writes per-session status plus the first KB of prompt/tool/notification payloads and the host app; `AgentHookConfig.describe` turns a call into "Editing X". Enabled installs are upgraded on launch.
- Dev Servers widget (`DevServers`): lsof LISTEN sockets of the user's own processes (no macOS services or app bundles except Xcode's developer tools), cwd via proc_pidinfo, Stop with SIGTERM after checking process-start identity.

### Messages and notifications
- Messages page (`MessagesPage`): `MessageInboxReader` reads recent chats and the open thread read-only from chat.db while the page shows (nothing kept); reactions fold onto their message; attachments show (images thumbnailed). Hide is local; Delete opens Messages' own confirmation (`MessagesScripts.deleteConfirmation`).
- A new message opens the page on its conversation (see Notifications under the notch); the reply field takes the first click.
- Replies (page and the banner's inline field) use `quickReply(_:toChat:)`, which verifies the exact chat id through Messages scripting before sending. Drafts are per chat (`ChatDrafts`); the inbox counts page consumers per display and rejects late reads (`InboxSession`).
- Incoming Messages and other apps' notifications (`SystemNotificationsReader`, usernoted's db2 store) need Full Disk Access and fail closed; message text is decoded by `TypedStreamText` (no unarchiving). Names and photos come from Contacts (`ContactNames`), asked only once incoming Messages is on and a message arrives.

### Clipboard
- History is memory-only unless Keep history after quitting is on; it excludes concealed/transient types and text shaped like a credential (`ClipboardSecrets`: private keys, prefixed tokens, JWTs, Luhn card numbers, `.env` blocks).
- Kept history, `clipboard-pins.json` and `scripts.json` are sealed by `SecureStorage` (AES-GCM, "MSE1" header; key via HKDF from a Secure Enclave P-256 agreement, or a keychain key without an enclave; `storage-key.json` 0600). Older plaintext files are read and re-sealed.
- Popup (`ClipboardPopup`, Carbon hot key `ClipboardPreferences.shortcut`, default ⇧⌘C, no permission): a non-activating key panel at the pointer, centre or under the notch with Maccy-style keys (↩ copy, ⌥↩ paste, ⌥⇧↩ plain text, ⌘/⌥1–9, ⌥P pin, ⌥⌫ delete, ⌥⌘⌫ clear). Pasting reactivates the previous app and posts ⌘V (Accessibility, asked on first use; otherwise clips are only copied). The shortcut keeps the clipboard service running.
- `ClipboardPreferences` (Settings → Clipboard): history size (default 200, up to 1,000), sort, search mode (exact, fuzzy, regex, mixed), pins position, preview, pause/ignore-next, clear options, auto-delete, and `ClipboardFilter` (kinds, apps, regex, pasteboard types).
- Entries carry `firstDate`, `copyCount` and `recognizedText` (Vision OCR on image clips, off the main thread); `ClipboardQuery` parses `@kind`, `@app`, `#collection`. Snippets, collections, pin keys ⌃A… (no N, P, U), drag out, colour picking, `ClipMenu` shared by popup, page and widget. `MaccyImport` reads Maccy's Storage.sqlite read-only, applying credential, app and private-type filters.
- Paste queue (off by default): each ⌘V or ⌥⇧⌘V puts the next clip on the clipboard 0.2 s later, in order or newest first. Seeing ⌘V elsewhere needs Accessibility, requested only when turned on. The closed notch shows only a count; turning it off puts the last copy back.

### Files
- **Tray** (`ShelfStore`, `ShelfView`; references only, removing never touches a file):
  - A grid of Quick Look thumbnails (`TrayThumbnails`: generated off-main, one bounded `NSCache` keyed by path and modification date, shared with the closed-notch screenshot). Screenshots and photos fill their tile, PDFs and video sit like a page with a type badge, plain-text files show their icon. Tiles show `TrayFiles.displayName` (no extension; today's screenshots drop the date).
  - The toolbar follows the selection: nothing selected shows the summary (count and size), Select All, Paste and Clear All; a selection shows Quick Look, file actions, Share, Show in Finder and Remove. Click, ⌘-click, ⇧-click, ⌘A; clicking between tiles or Escape deselects; Space previews, Return opens, Delete removes, ⌘C copies the files; dragging carries the whole selection with its thumbnails. The context menu acts on the selection when the item is part of it.
  - Removals and Clear All show an Undo bar for six seconds (`ShelfStore.undoSeconds`, also ⌘Z) that restores items in place. Errors clear themselves after six seconds.
  - Missing files (`TrayFileState.inspect`, on a worker; a file still missing 0.6 s later counts): a moved or renamed file is followed through its bookmark; a deleted or trashed one leaves the list with one quiet notice; a file on an unmounted volume or an evicted iCloud file stays dimmed with a drive badge (Locate and "Remove … on disconnected drives" only there).
  - The saved list (`tray.json`, `basket-<id>.json`) is read, bookmark-resolved (never mounting) and written on one serial worker (`ShelfDisk`); a damaged list is recovered explicitly with a backup. Pasted content is staged with readable names (`TrayFiles.stagedName`: first line of text, a link's host, "Pasted Image <date>").
  - Paste of files/text/images/links, AirDrop and Share, Copy Text (Vision), Remove Background (macOS 14+).
- **File baskets** (menu → File Baskets): frosted circles parked anywhere (default bottom-right beside the Dock); the circle shows its two newest thumbnails fanned and a count; drop files, links, images or text on one, click to open a panel that grows away from the nearest corner, drag to move; folding returns the circle exactly (the open panel may sit higher to clear the Dock).
  - Remove Basket (the circle's right-click menu, the panel's basket menu or a Tray-page chip) deletes its list only (baskets hold references). One `ShelfStore` per basket (`BasketWindowController.store(for:)`); once a basket exists the Tray page shows chips (with counts) for the Tray and each basket. Positions and open state persist (`fileBaskets.origin.<id>`, `fileBaskets.open`).
- **File Converter** (menu → File Converter; Settings → Files):
  - Shift during a file drag shows a frosted wheel of formats around the pointer; Option-Shift shows tools (compress, metadata, resize, extract audio, GIF, snapshot, under 1 MB, split/merge PDF, zip/unzip).
  - `ConverterWheel` watches global mouse drags (hit-testing in the panel's unflipped window coordinates) and the drag pasteboard (no permission); its centre is a `FileGlyph`, not a thumbnail.
  - `FileConverter` uses only ImageIO, PDFKit, AVFoundation, NSAttributedString and ditto/zip, and offers only formats this Mac can write (no MP3, MKV, WebM, OGG or RAR).
- **File Tools** (`FileToolsView`; menu, Finder Services, Shortcuts) share the converter's jobs:
  - Outputs are written to hidden staging names, then renamed to collision-safe final names beside the original (Downloads when that folder is read-only); originals are never edited.
  - Jobs keep per-input errors and successful outputs, support cancel/retry, and show progress cards that reveal results.
  - Transparent images stay transparent; compression must reduce bytes; multi-frame images need explicit first-frame extraction. Favourites, recents and named presets.
- **Folder watching** (Settings → Files → Downloads & folders, opt-in): only files arriving after activation, excluding browser partial names, once metadata is unchanged for six seconds (`CompletedFileTracker`; a heuristic, not proof the writer finished).
- **Screenshots** (`ScreenshotWatcher`, off by default): NSMetadataQuery for screen captures created since start (also by name, since macOS 27 doesn't set the flag), added to the Tray with a closed-notch thumbnail (from `TrayThumbnails`, never a full decode on main). A screenshot deleted after capture (e.g. from the floating thumbnail) leaves the Tray on its next check.

### Timers and Focus
- Up to three `TimerService` slots (keys `timer`, `timer2`, `timer3`; `timers.count`), each with its own tint (orange, cyan, pink) on its ring and in the closed notch; cards have no header.
- Focus timer (`PomodoroModel`): the moon button runs the Shortcuts "MacSpaces Focus On/Off" (found by name, one-time guided setup); Focus Off undoes only what MacSpaces turned on (`FocusSilencing`).

### Clock
- One Clock widget, styles Regular, Dot and Map (`WidgetOptions.ClockStyle`), with up to six places (`clockPlaces`, `maxPlaces`; "local" is here). Dot: `DotTime` digits at a fixed width, city in small capitals and a ±1 day mark. Map (`MapClock`, `ClockGeography`): a 96×37 dot land grid shaded by the sun, a pin per place (labels only on Large), and one dropped pin (`WidgetOptions.clockPin`) taking the nearest zone from `/usr/share/zoneinfo/zone.tab`.
- The Clock page (`NotchTab.clock`) is the Map at page size: hover readout with country, Apple geocoding for places (saved as `zone#Name#lat,lon`), a ±12 h scrubber, place chips with search. `WidgetOptions.isCurrent` marks the first saved place in this Mac's time zone as the current place (the accent pin); with labels drawn, the large readout appears only for a dropped pin.

### System page and the power helper
- System stats (`SystemStatsWidget(detailed:)`): CPU, memory and network graphs (network scaled to its own peak), memory used, swap, free disk, load, uptime, thermal state.
- The page is 860 wide with three untitled sections: System stats | Overtime | power (`CableManagementCard`), with `BatteryPill` spanning the last two underneath (`SystemAppView`). `PageCard` titles are optional; the Shortcuts page still uses them.
- Overtime (`OvertimeCard`): Low battery (`AgentPowerAlert`, 20%: hooks tell Claude Code and Codex sessions to save and commit), Agents keep running (`LidClosedAwake`), Keep awake (durations and a display chip in one row).
- Alignment: the power column's rows (`PowerRow`) use Overtime's row metrics (30 pt icon circle, 10 pt gap, 6 pt vertical padding), so the two columns line up row for row. `BatteryPill` is 44 pt tall with a 9 pt bottom inset, matching the stats graph block; its left edge is the row icons', its terminal the switches' right edge, the bolt centred in the icon column, the level at the titles (40 pt) and the time at the power column's titles (`timeInset`). Its fill is the tint at 38% so text never changes colour over it.
- The Home Battery widget is the gauge and level (plus one line only for time to full, not charging, or a warning), and its popover (`BatteryDetailsView`) has health, cycles, temperature and Low Power Mode.
- One model, `PowerSourceMonitor` (`services.powerMonitor`): every power view reads its committed `state` (`BatteryState`: unavailable, noBattery, onBattery, low, charging, fullyCharged, notCharging, draining). `rawState` puts full (100%, or Is Charged at 95%+) ahead of a top-off trickle; low enters at 20% and holds until 23%. `BatteryStateDebouncer` commits an unplug at once, a plug-in after 2 s unchanged, sub-state changes after 2 s in the first minute on power and then charging → not charging after 10 s, back to charging after 30 s; draining and onBattery ↔ low commit at once. `batteryLevel`, `hasBattery`, `hasReading` and `isOnExternalPower` stay raw IOPS for `AgentPowerAlert` and `LidClosedAwake`.
- Sources, nothing else:

  | Shown | Source |
  |---|---|
  | Level, state, time to full | IOPS (run-loop source, `kIOPSNotifyTimeRemaining`, wake); time to full only while charging, filtered by `TimeToFullFilter` (down at once, up after two higher updates by 10 min or 15%) |
  | Time left on battery | IOPS `kIOPSTimeToEmptyKey`, only on battery or low, filtered by `TimeToEmptyFilter`: nothing for the first 5 min after an unplug, then changed only after two updates in the same direction differing by 15 min or 20% |
  | Maximum capacity, condition | `system_profiler SPPowerDataType -json` (`BatteryHealth`) at start, every 6 h and when the popover opens with a reading over an hour old; a missing key is left out |
  | Cycle count, charger, temperature | AppleSmartBattery (`CycleCount`, `AdapterDetails`) and AppleSmartBatteryPack (`Temperature`), read on each IOPS change, 3 s and 10 s after a plug-in, and the temperature each minute while the popover is open |
  | Live input | `PowerInputSampler` |

  "On battery for …" is the time since the unplug commit. Both times show rounded (`BatteryStatusText.span`: 5 min steps under an hour, 10 min above, "10+ h").
- Power column (`CableManagementCard`), rows in order: the verdict (thumbs up "Keeping up" for charging, fully charged and not charging, with "Charging, with nothing spare" while the input is at the connection's limit; orange thumbs down "Falling behind" for draining; "Not plugged in · On battery for …" unplugged; "On power" on a desktop), Low Power Mode (`LowPowerMode`), Battery health ("87% capacity · 343 cycles", or orange "Service recommended"), then every connected Bluetooth device with a battery in one row. The charger (`ChargerInfo`: AdapterDetails Name, "pd charger" as "USB-C charger"; `connectionWatts` = AdapterDetails Watts; `ratedWatts` from the name), a limit note when the rating exceeds the connection by 10 W or more, and the watts coming in are only in the verdict's help.
- `PowerInputSampler` (nested in the model; only the power column and a drain check retain it): a 1 s `.common` timer reads `SMCPowerSensors` (PDTR watts, VD0R volts). Watts: the 30 s mean, first shown after 3 s of samples, then re-evaluated every 5 s once 10 s exist and changed only by 2 W or 8%. Volts: snapped to the USB-C steps (5, 9, 15, 20, 28, 36, 48 V) within 10%, changed after 10 readings in a row. Release and a gap over 5 s forget the samples but keep the shown values; a plug or unplug and wake clear everything. `isLive` drops after 10 s without a reading. The UI uses it for `atLimit` and the verdict's help.
- `SMCPowerSensors` caches each key's size, type and attributes; integers and `sp78` are little-endian when attribute bit 0x04 is set, `flt` always (`decode`). Failed opens back off 5 s, 30 s, then 5 min; failed key lookups retry after a minute.
- Colour: `PowerPalette.tint` is orange only for low and draining, the theme accent otherwise; "service recommended" is the only other orange text. `BatteryGaugeView` (widgets, popover) and `BatteryPill` (System page) are the only battery glyphs, each with the bolt only while charging.
- Notices beside the notch (`PowerNotice`, `PowerActivityGaugeView`/`PowerActivityLevelView`, the gauge and the level only) come only from commits and the drain detector: plugged in (4 s), unplugged after at least 2 s on power (4 s), low at 20/10/5% (8 s, with a notification) and draining (8 s, with a notification, once per plug-in). A notice of the same kind is merged; a new one replaces it. The drain detector (`DrainDetector`) needs 5 min on power, the level 3 points under its peak and a 60 s input mean of at least 85% of the connection's watts; it clears when the level rises a point or charging holds a minute.
- `LidClosedAwake` runs `pmset -a disablesleep 1/0` (the only way to run lid-closed) through the privileged helper when approved, otherwise osascript with administrator privileges; state is read back from `pmset -g`; it is turned off without a prompt at quit and once per low-battery stretch.
- Power helper (`Helpers/PowerHelper`, target `MacSpacesPowerHelper`, embedded at Contents/MacOS with `dev.opensource.MacSpaces.PowerHelper.plist` in Contents/Library/LaunchDaemons):
  - Registered with `SMAppService.daemon(plistName:)` from the row's "Skip the password" chip, then allowed once in Login Items. The row's context menu has Open Login Items and Remove Helper.
  - Its XPC contract (`PowerHelperProtocol`) is exactly four argument-free calls: `preventSleep`/`allowSleep` (`/usr/bin/pmset -a disablesleep 1/0`) and `enableLowPowerMode`/`disableLowPowerMode` (`-a lowpowermode 1/0`).
  - The helper accepts only `dev.opensource.MacSpaces` from team 28LJG7MXT3 (`setCodeSigningRequirement`), the app checks the helper the same way, and it exits after a minute idle.

### Teleprompter, Dictation and Meetings
- Teleprompter (`ScriptPrompter`, scripts in Application Support/scripts.json): `PrompterPanel` under the notch with `sharingType = .none`; scrolls at a wpm or follows the voice (`VoiceFollower` + the pure `ScriptAligner`). Voice mode requires on-device recognition (`OnDeviceSpeech`) and otherwise scrolls; mic/speech are asked only in voice mode.
- Dictation is a Nook page: explicit Start, on-device recognition only, editable text, Copy or Paste into the app captured on open; it stops when closed or left and keeps no audio.
- Meetings is a Nook page with provider-specific Zoom and Google Meet (Safari/Chrome) controls (`MeetingControls`): a closed set of actions, never user JavaScript; Meet checks the selected tab's https://meet.google.com origin again in the page; unknown or ambiguous states are refused; English control labels are required. Opening either page requests nothing.
- `MeetingCountdown`: closed-notch countdown for video meetings from 10 minutes before to 5 after; it uses the events service only when Calendar access already exists.

### Weather, Calendar, Battery and Bluetooth
- Weather demand comes from its widget, visible page and bounded dock warming; Open-Meteo with an IP-location fallback. A versioned forecast cache in the app cache directory is read/written off-main, retaining matching-unit conditions up to six hours across launches. Reopens reuse forecasts under 15 minutes old; scheduled 15-minute polls force refresh. Hover warming never requests Location permission; the visible widget/page can request it. There is no duplicate hover-details popover.
- Calendar via EventKit; the year progress and month grid follow Aaron Lichtman's DayDrop.
- The Battery widget and visible System page start Bluetooth monitoring: paired-device reads plus the macOS connected-device report when IOBluetooth omits accessories; battery reads cached 30 s, connection fallback every 4 s; unknown stays unknown; earbud and case levels separate. Power uses the internal battery's capacity ratio and charging flag, not the presence of external power.
- Network use is limited to what features need; README's Privacy section is the public list (Open-Meteo, ipapi.co, LRCLIB, lyrics.ovh, Spotify oEmbed, iTunes, Deezer, frankfurter.app, GitHub). Keep it current when adding a service.

## Appearance and themes

- `ThemeFamily` gives paired light/dark palettes; `AppearanceMode` is System/Light/Dark. `ThemeStore` holds only the family, mode, lyric style, haptics and Reduce Motion; `ThemeStore.accent` is the theme's accent everywhere. A saved `theme.notchPreset` is read once through `ThemeFamily(legacy:)`.
- Drawers (`ThemeCollection`), each a multiple of five, in the order Core, Terminal, Nature, Tech, Glass:
  - **Core**: exactly MacSpaces (Noir), PowderMeet, Heartable, KemoSabe, Tsukumo, in that order. A saved Noir opens as MacSpaces; the earlier MacSpaces blue is Midnight in Terminal.
  - **Terminal**: classic editor palettes, Karma and single colours, by colour, Custom last (`CustomThemeColors`: background and accent; text pure white or black).
  - **Nature** (25): five rows (Bloom, Forest, Earth, Water, Sky), each by colour except Sky. Every Nature theme draws a photo background (HEIC imagesets, `Theme<Name>.imageset`) with a shader (`FloralBreeze.metal` for flowers, `NatureMotion.metal`).
  - **Tech**: Synthwave, Circuit, Code Rain, Warp, Rainbow (`rainbowFlow`, a flowing colour field).
  - **Glass**: Clear, Frost, Glass, Smoke, Custom. Only these have `ThemeFamily.glassTint`; no effects.
    - Clear is fully transparent (a 1% fill keeps hit-testing); Smoke is always dark and Frost always white (`fixedScheme`); Glass follows light/dark; Custom (saved id `tinted`, `TintedGlassColors`) picks tint, accent, strength and blur (default neutral slate).
    - Glass makes the open Nook and dock capsules see-through (`NookBackdrop`: Liquid Glass `.clear` on macOS 26+, a behind-window blur before); the closed notch and other windows stay solid.
    - Settings cards preview Glass over a Canvas stand-in desktop.
- Outside Core, ordering by colour is `ThemeCollection.byColour` (greys, then hue red → pink) (unlabelled). Every family is in exactly one drawer; Settings shows collapsible drawers and the Nook menu submenus from the same catalog.
- Every scene theme has exactly one effect (`ThemeFamily.motif`, `ThemeMotif`: original geometry drawn in code, faded toward the centre) behind the open Nook and on its card. Effects run up to 30 fps (flower photographs 20 fps, `ThemeMotifView.framesPerSecond`) only while the Nook is open, never under Reduce Motion, and hold a still frame on cards. Preview images carry no appearance or variant labels.
- Retired themes map to replacements in `ThemeFamily.replaced`.
- App icon: `Sources/Resources/AppIcon.icon` (Icon Composer: white `mark.png` over a black image layer, since macOS 26 lightens a solid fill); Xcode derives the rounded icon for macOS 13–15. The mark (a solid disc with the notch cut from its top, on a 100-unit grid) is drawn by `Scripts/generate-app-icon.swift`, which also writes `MacSpacesIcon-master.png` for Settings and the installer. The website icon is the master in a black rounded square (inset 64 on 1024). App icons are independent of appearance.

## Build, release and updates

- Bundle `dev.opensource.MacSpaces` (keep it stable for settings and update verification); team `28LJG7MXT3`; keychain profile `MacSpaces`. Never commit credentials, generated projects or release artifacts.
- The one package is SwiftTerm (MIT, pinned exactly in `project.yml`; licence in `Sources/Resources/Acknowledgements.txt`). Its build plugin means every `xcodebuild` passes `-skipPackagePluginValidation` (Makefile, CI, package-release.sh).
- `make` builds Release locally. `make release` runs `Scripts/package-release.sh`: universal Release build, Developer ID signing with hardened runtime (the power helper first, with its own identifier), app notarization and stapling, DMG creation, DMG notarization and stapling (two rounds so both pass Gatekeeper offline; `notarytool --timeout 60m`), then signature, architecture and Gatekeeper checks on the mounted app.
- CI (`.github/workflows/ci.yml`, macos-26): all check scripts, plus a Debug arm64 compile check with cached Swift packages; a newer push cancels an older run. A passing local build is not enough: CI must pass on the exact commit being released.
- **Shipping**: bump `project.yml` and `RELEASE_NOTES.md` (current version only, named in bold), then run `Scripts/ship.sh` in the background with any commit trailer in `SHIP_TRAILER`. In order it:
  1. runs six checks;
  2. makes a new root commit `MacSpaces X.Y` and pushes it with force-with-lease;
  3. runs `make release` while waiting for CI on the full commit SHA (`gh run list --commit` ignores short SHAs);
  4. tags `vX.Y` and runs `Scripts/publish-release.sh` (Latest; refuses development builds; adds one hidden `macspaces-build` marker);
  5. updates the Homebrew cask, then deletes every older release and tag, first adding each release's download count to `downloads.tsv`.
- **Downloads**: deleting a release deletes its GitHub download count, so `downloads.tsv` (repo root, git-ignored) is the only record of earlier releases' counts; never delete it. Counts before 3.17 were lost. `Scripts/downloads.sh` prints each release's count, the current release's live count and the total. The installer, Homebrew and the in-app updater all download `MacSpaces.dmg`, so the counts are downloads, not people: a release's count is roughly its new installs plus the installs that updated to it.
- `main` is a single root commit, `MacSpaces X.Y`, with no parent; each release replaces it. No recovery bundles, backup branches or spare app copies. A replacement installer for the same version updates that release. `CHANGELOG.md` gets an entry for the version.
- **Docs-only updates**: `Scripts/publish-docs.sh` replaces the root commit and moves the current tag, installer unchanged. It publishes `README.md` and `Demos/` only and refuses if anything else differs from the published commit; other docs (this guide, the changelog) ship with the next release.
- **Versions**: `CFBundleShortVersionString` is the public version (2.x used `major.build`, 2.32 … 2.100; from 3.0 plain names; 1.0.0 predates both). `CFBundleVersion` is an internal integer that must exceed every published build, since updaters compare builds. `check-release-policy` enforces this.
- **Updater** (`UpdateService`, `ReleaseRevision`):
  - 1.14 and 2.38+ read releases/latest; 2.36 and 2.37 read the release list and take the newest non-draft release of their major version (`ReleaseRevision.newest`).
  - Updates download automatically by default, look hourly while running and check GitHub once six hours have passed since the last check, download only over https from GitHub's release hosts (`isTrustedDownload`), and verify the app's version, build, bundle id, signing team (`signingTeam(fromCodesignOutput:)`), minimum macOS and architecture before asking to relaunch. A build this Mac can't run is remembered and skipped.
  - 1.14's updater can't check the minimum macOS, so the current release must keep running on macOS 13.
- **Homebrew**: `zlichtman/tap/macspaces` is the only cask (`depends_on macos: :ventura`; run `brew style --cask` before pushing the tap); `cask_renames.json` moves old `macspaces@beta` installs to it.

## Checks and QA

Check sources live in `Tests/` and compile with `swiftc` against the real sources they test. CI runs every script; `ship.sh` runs the six marked ✓.

| Script | Source | Guards | ship.sh |
|---|---|---|---|
| check-release-policy | inline Python | `project.yml`/Info.plist versions match; version format; rising build; RELEASE_NOTES names the version; every privacy API in Sources has its usage string and hardened-runtime entitlement | ✓ |
| check-update-revisions | UpdateRevisionChecks | version/build comparison, replacement and malformed releases, pre-release channel, trusted download hosts, codesign TeamIdentifier parsing (an empty `TeamIdentifier=` is no team) | ✓ |
| check-core | CoreChecks | feature catalog, lazy lifecycle ordering, rollback, cycles, action safety, cancellation, Focus cleanup | ✓ |
| check-appearance | AppearanceChecks | family/mode persistence, legacy preset migration, system resolution, text contrast | ✓ |
| check-settings-search | SettingsSearchChecks | multi-word queries, punctuation, accents, ranking, permission routes, all eight destinations | ✓ |
| check-power-helper | inline shell | helper plist, exactly four XPC calls, fixed `pmset` arguments, no shells, client requirement and team, `isMainBundle` guards, no sudoers anywhere | ✓ |
| check-playback | PlaybackChecks | seek bounds, capabilities, wrong-player prevention, artwork matching, Spotify covers, clock anchoring, poll pacing, reused scripts | |
| check-lyrics | LyricsChecks | LRCLIB record decoding, song matching, LRC rests and offsets, uncensoring, line timing (lead, rests, spans, next change), Typewriter timing, the disk cache | |
| check-agent-hooks | AgentHookChecks | hook payload fields and descriptions; merge keeps user hooks, no duplicates, clean removal | |
| check-notes | NoteChecks | note migration, conflicts, delete/restore, schema preservation | |
| check-clipboard | ClipboardChecks | capture, credential/concealed exclusion, paste queue, search modes, pins, filters, OCR text, snippets, auto-delete, Maccy import, encryption at rest | |
| check-file-tools | FileToolChecks, TrayChecks | image/PDF/batch jobs, cancellation, collisions, completed-file watcher; Tray references (moved followed, deleted/trashed gone, unmounted and iCloud-evicted kept), tile and staged names, undo order | |
| check-calculator | CalculatorChecks | arithmetic, functions, units, currencies, bad input | |
| check-prompter | PrompterChecks | voice following, noise rejection, on-device-only voice, protected script library | |
| check-messages | MessageChecks | notification routing (page vs card, Nook in use, locked/hidden, card destinations), recipient identity, uncertain sends, per-chat drafts, inbox consumers, script compilation; no messages sent | |
| check-incoming-messages | IncomingMessagesChecks | no history import, incoming filtering, replay prevention, read-only store, schema failure; also fails if any `sqlite3_open` in Sources lacks `SQLITE_OPEN_READONLY` | |
| check-coding | CodingChecks | Codex snapshot dedupe, limits, 14-day window, project names, synthetic messages | |
| check-window | WindowChecks | stationary desktop panel policy, Spaces, full screen, focus, geometry, 120 content-size transitions | |

Debug regression checks (`Sources/Debug`, run at the start of every FeatureQA and website run):

- `InteractionRegressionChecks`: Clock current place, dock Pin/Close persistence and Home last, saved-dock migrations and removal, sticker matching (and weak-word and broken-heart negatives), `libraryGroups` covers every widget, layout robustness (repeated widgets, stacking, size persistence, retired style fields), converter wheel segments. It doesn't pin default widgets, dock order, settings page order/titles or pixel sizes.
- `DeviceRegressionChecks`: power source semantics, SMC byte order, battery state and debounce, wording, live input filters, System Information and charger parsing, the drain detector and Bluetooth component battery parsing.
- `ReviewRegressionChecks` (scope `review-regressions`) and `WidgetRemovalRegressionChecks` (scope `widget-removal`).

### Running the Debug harnesses
Build Debug with the harness's own bundle identifier (each refuses to run otherwise); all use isolated preferences and synthetic data.

- **FeatureQA**: `PRODUCT_BUNDLE_IDENTIFIER=dev.opensource.MacSpaces.FeatureQA`, launch with `MACSPACES_FEATURE_QA=<output dir>` and optionally `MACSPACES_QA_SCOPE=<scope>`. `MACSPACES_CONVERTER_INPUT=<folder>` (scope `converter`) runs every action on samples; `MACSPACES_CONVERTER_BG=white|black` (scope `site-converter`) renders on a flat colour (a pair gives real alpha); `MACSPACES_DEMO_THEME=blossom` switches some site scopes to Blossom.
- **AppearanceQA**: `dev.opensource.MacSpaces.AppearanceQA`, `MACSPACES_APPEARANCE_QA=<output dir>`.
- **Website demo**: `dev.opensource.MacSpaces.WebsiteDemo`, `MACSPACES_WEBSITE_DEMO=1`, `MACSPACES_DEMO_OUTPUT` (default `/private/tmp/macspaces-nook-demo`).
  - `MACSPACES_DEMO_KIND` = `clips` (`WebsiteDemoClips`; `MACSPACES_DEMO_CLIPS` picks clips, e.g. `music-showcase`, `readme-hero`), `notch`, `home` or `2.x`; `MACSPACES_DEMO_THEME=everforest|blossom`.
  - `MACSPACES_DEMO_TRACKS` (JSON keyed by name: title, artist, album, duration, cover, short lyric excerpt); `MACSPACES_DEMO_COVERS` (cover folder, default `/private/tmp/macspaces-covers`, never committed).
  - `MACSPACES_DEVICE_AUDIT=1` logs device counts only.
- `MACSPACES_VISUAL_QA=1` lets a second Debug instance run past the duplicate guard.
- Shortcuts and timers have Debug-only previews (`ShortcutsService.setPreview`, `TimerService.setPreview`); the real Shortcuts list is never read in captures.

Additional scopes: `performance` covers slow/coalesced Mission Control, hover cancellation/suppression, hover off the closed notch, nonblocking statistics, retained scene/artwork generations, persisted Weather cache/polling and synthetic Mirror ownership/session/readiness/error handling; `settings-update` covers typed/native widget drops and captures Home, Appearance, app settings and empty Tray.

Scope index (`FeatureQAHarness`): activities, basket (basket panel and circle, the Tray page browsing, selected, offline, notice, Undo bar and in Midnight/Everforest), clipboard-popup, clipboard-popup-live (real panel focus and keys), clipboard-queue, clock (also clock-page.png), coding, communication-pages, converter, dock-controls, dock-settings, lyric-styles (every style and scene), lyrics-258, messages-inbox, music-layout, power-permissions (battery-row.png, cable-card.png), release-255, review-regressions, review-tools, secure-storage (real enclave), site-converter, site-green, site-themes (every drawer open), stickers, system-page (also the Battery widget sizes), timers, tools-254, wheel, widget-removal.

Before shipping visual changes, inspect Settings and the Midnight and Everforest scenes.

## README and demo captures

- README sections: Requirements (lowest macOS and every newer-macOS feature, from the `#available` checks), Install, the Nook, Pages, Home Widgets, the Closed Notch, Clipboard History, Files, Themes, Settings, Privacy (permissions table and network services), Uninstall, Build From Source, Contribute, Credits. Update feature text with every release.
- Images live in `Demos/2.x/screenshots`, use real songs, and are the website's captures (`LIFE/PROJECTS/PORTFOLIO/public/projects/macspaces/media`, `page-*` each in its page's theme), converted with `cwebp -q 84 -m 6` and laid out as HTML `<img width="49%">` rows (no Markdown tables with empty headers). Every file there must be referenced by the README. Videos live on the website, not in the repo.
- Website reels come from `WebsiteDemoClips`: Music is one native-60 fps reel (`music-showcase`: songs in matching Nature themes with short lyric excerpts); the README hero is `readme-hero` (Music in Blossom with a Stickers lyric); the site dock is `WebsiteDemoNotch.siteDock` (nine apps plus Home; a captured page outside it is added for its shot).
