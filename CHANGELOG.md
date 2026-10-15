# MacSpaces changelog

What changed in each version, newest first. The current state of the code is described in
[AGENTS.md](AGENTS.md); the public notes for the current release are in RELEASE_NOTES.md.
Version numbers: 1.0.0 builds 10–14; 2.x was `major.build` (2.32 … 2.100); from 3.0 plain names.

## 3.15 (build 116, 2026-10-15)
- Move Mission Control window queries, system sampling, agent status scans, Tray availability/details/icons and artwork washes off the UI thread. Coalesce work and reject results after cancellation, service stop or a newer selection.
- Retain the selected decoded theme image, reuse identical MediaRemote artwork and the Core Image context, reduce overlapping blur effects, defer decorative animation/page startup, and isolate closed-lane subscriptions from the shell. Geometry updates follow layout changes instead of media/timer ticks. Reuse fresh Weather snapshots.
- Replace the widget sheet/menu with an inline visual gallery, typed drops into the layout and native Nook, a temporary drag pin, and sample previews that start no services. Give each widget one canonical size and simplify the Home editor.
- Keep all six lyric styles in Appearance with Poster as the default. start theme drawers closed; alphabetize unused dock pages; keep the Tray chip row without baskets; put Updates first in General.
- Remove the redundant Weather widget hover/click popover; its expand action opens the full Weather page.
- Remove redundant Clock, Weather and timer preferences. Home has the regular clock, the Clock page has its interactive dot map, and Weather follows the system temperature unit. Move battery level into a fourth matching statistics ring and give the upper System columns three equally sized rows.
- Standardize all app-page dimensions, compact System with statistics/networking below its controls, and show page controls only when present, between apps and Settings. Home uses a regular clock, has no size menu or separate inspector, and fills gallery rows without trailing empty cells. Selected previews support Delete and Forward Delete.
- Keep Poster lyric headlines at their natural width beside short trailing phrases so words do not spread across the entire lyric area.
- Remove the Music dock sound-output/connected-device menu and its device-routing code. Only Apple Music shows the playlist control; other players leave no extra capsule or gap.
- Warm safe dock services during hover/opening, remove the fixed page-service delay, persist recent same-unit forecasts off-main, and force scheduled Weather polls so fetch latency cannot skip every other refresh. Begin Mission Control checks during the hover delay.
- Keep four smaller System rings within the original group width, top-align statistics/graph headers, and keep the statistics strip clear of the bottom edge.
- Reuse one Mirror camera session/queue, cache camera discovery off-main, preconfigure authorized cameras without starting capture, remove the fixed camera delay, wait for actual frames, handle capture interruptions/errors and detach previews before removal transitions.
- Remove iCloud conflict plist copies and exclude future copies from Git and app resources.
- Add performance, cancellation, resource-reuse, settings migration, native drop and synthetic camera lifecycle regression coverage.

## 3.14 (build 115, 2026-10-14)
- System page redesign: no section titles; a wide battery pill under Overtime and the power
  column shows the level and the time to full or, new, the time left on battery (macOS's
  estimate, held steady); the power column answers whether the charger keeps up with a
  thumbs up or down, then Low Power Mode, battery health and other devices' batteries.
  Watts, volts and the charger's name moved into the verdict's help. Everything lines up
  with the rows, switches and graph beside it.

## 3.13 (build 114, 2026-10-14)
- Settings sidebar: the top three pages (General, Appearance, Permissions) get a Core label,
  so every section is labelled: Core, Notch, Tools.

## 3.12 (build 113, 2026-10-14)
- Battery is simpler: the Home widget is just the battery icon and level, with one line only
  for time to full, not charging, or a warning; details stay in its popover. The battery row
  left the System page's Overtime, and Cable management shows no placeholder before its
  first reading.
- Settings sidebar: Permissions joins General and Appearance at the top, so the sidebar has
  three sections (the app, Notch, Tools).

## 3.11 (build 112, 2026-10-14)
- Settings sidebar: General, Appearance, then a Notch section (Home, Apps, Activities), a Tools
  section (Files, Clipboard), and Permissions, with small non-collapsing labels.
- The System page's description in Notch → Apps is shorter.

## 3.10 (build 111, 2026-10-14)
- Battery and charger are now two separate things on the System page: Overtime ends with
  your battery, and a new Cable management column shows the charger macOS reports, what
  this connection can give, the power coming in averaged over 30 seconds, and the charger's
  voltage.
- Every battery figure now comes from macOS: level, charging state, time to full,
  and maximum capacity and condition exactly as System Information shows them.
- Fixed wrong wattage readings: the Mac's power sensors were read in the wrong byte order,
  which showed a battery drawing about 13.6 W while it was resting and flipped charging
  and draining.
- Nothing flickers when you plug in or unplug: the state waits until macOS has settled, and
  a full battery stays "Fully charged" while it tops off.
- Removed the power diagram, battery watts, and time left on battery (including "if
  unplugged"), which were estimates that jumped around.
- The warning that the charger can't keep up now appears only when the battery has fallen
  three points while plugged in and the charger is giving nearly all it can.
- Battery text is larger and easier to read, with one battery icon and one colour (orange
  only for low battery or a charger that can't keep up).
- Review fixes: unplugging clears a drain warning; the time to full counts distinct macOS
  updates and clears while macOS recalculates (after wake); "Last charger" is remembered;
  restarting the power service or waking starts a fresh session; the battery popover from
  the System page lists Bluetooth devices and never holds the Nook open; the Large widget
  never shows "0%" without a reading; the charger detail no longer resizes the column.

## 3.9 (build 110, 2026-10-14)
- Battery: plugged in with the battery giving while the charger delivers well under its
  contract is `State.batteryByChoice` (macOS running on the battery, as it does at times when
  full), shown in the theme colour with no alert. "Charger can't keep up" and its notification
  are only for a charger near its limit. Covered by DeviceRegressionChecks with live readings.
- Settings sidebar: Notch Apps, Notch Home and Activities as three plain items (no group).
- Live power: `SMCPowerSensors` reads the SMC every second (power in, its volts and amps, battery
  current, battery temperature); the registry's figures only refreshed every minute or so, so
  the watts sat still while the diagram moved.
- System page: the middle section is Power (flow, status, charger and its agreed and live terms);
  the battery is the fourth Overtime row.
- The menu bar battery is gone; Low Power Mode is in the battery popover.
- README: the Catacombs page image is in the Bamboo theme over its bamboo desktop.

## 3.8 (build 109, 2026-10-14)
- Power flow: particles (soft dots with short tails) glide along each band's curve instead of
  a sweeping highlight; still with Reduce Motion.
- Battery menu bar icon: Battery in Menu Bar toggle in the MacSpaces menu, Hide from Menu Bar
  in the battery menu, and the ⌘-drag tip in Settings → General → Menu bar.
- GitHub (Terminal page): the username fetch waits for typing to pause and drops replies for
  a name that changed; an unknown account or an unreachable GitHub is said plainly
  (`contributionsProblem`) and retried in five minutes instead of an hour.
- Battery direction: the current's sign read positive while discharging, so unplugged Macs
  showed a charging band. Unplugged, the battery now always gives; plugged in, charge or
  drain is input less system load (macOS's BatteryPower). Covered by DeviceRegressionChecks.
- Time estimates: macOS's "until fully charged" and time remaining are read with every
  sample (`systemMinutesToFull`/`systemMinutesToEmpty`), ahead of our own estimate.
- Charging is drawn in the theme's accent; the charger-to-Mac band is neutral.
- Stickers: the star breathes and sways slowly instead of a sharp |sin| pulse, and sticker
  motion follows `Design.demoTimeScale` so slowed website captures keep real speed.
- Lag: theme cards draw small thumbnails made off the main thread (`MotifThumbnails`;
  decoding the 25 full-size HEIC photos took about half a second), and found lyrics are
  kept per track so returning to the Music page doesn't search LRCLIB again.

## 3.7 (build 108, 2026-10-13)
- Fixed 3.6 hanging at launch (100% CPU, nothing opened): SwiftUI writes the battery
  menu's `isInserted` binding back on every scene update, and the @Published setting
  announced even an unchanged value, re-evaluating the scene in a loop. The binding now
  writes only real changes. The menu bar icon is also drawn once per state and reused.

## 3.6 (build 107, 2026-10-13)
- Power flow redrawn as a split diagram (`PowerSankey`) with one plain headline and the
  charger's workload; `PowerFlow` adds temperature (from `AppleSmartBatteryPack`), pack
  voltage and current, mAh, a `State` and time estimates; `PowerFlowSampler` averages three
  readings.
- System page Battery section, Large Battery widget and battery popover share
  `BatterySummaryView` / `BatteryFactsGrid`.
- Alerts: draining while plugged in (notice and notification), a 3 A cable after plug-in,
  and the agreed watts beside the gauge (`activityValue`). 3.5's note said the plug-in
  notice showed the wattage; it only reached VoiceOver until now.
- Menu bar battery menu (`BatteryMenu.swift`, off by default) with Low Power Mode
  (`LowPowerMode`); the power helper gains `enableLowPowerMode`/`disableLowPowerMode`
  (fixed `pmset -a lowpowermode 1/0`; check-power-helper allows exactly these four).

## 3.5 (build 106, 2026-10-13)
- Power flow: `PowerFlow` reads AppleSmartBattery's `PowerTelemetryData`, battery voltage and
  current, and the USB-C contract (`AdapterDetails`, `UsbHvcMenu`); `PowerFlowView` animates
  charger → Mac → battery. A 3 A contract from a charger offering more is flagged as a likely
  cable limit. Shown in the battery popover and the System page's new Battery section.
  The plug-in activity includes the agreed wattage.
- System page: three sections (860 wide); page cards have text-only headers; the dock icon
  is `gauge.with.needle`.
- Permissions page rewritten (`WidgetAccessSettings.swift`, `PermissionStatusModel`): real
  Automation (`AEDeterminePermissionToAutomateTarget`, no prompt) and Full Disk Access
  status, re-read every 2 s while open, and an Allow… / Open Settings button on every row
  that isn't allowed, in both sections.
- Clock page: a map click adds the place (refined by the geocoder); no pin or dot readout
  there; the places bar falls back to tighter chips, an icon-only Add and a narrower
  scrubber before scrolling.
- Settings: Notch sidebar group (Apps, Home, Activities); the Dock card moved to Apps with its
  page list first.
- Menu bar: Close Nook while any Nook is open (`NookPresence`).

## 3.4 (build 105, 2026-10-13)
- AGENTS.md describes how things work, without a "standing rules" section.
- `ship.sh` polls the CI run instead of `gh run watch`, so a GitHub API error no longer stops a release while CI is still running.
- The repository was recreated (same name, same code and release history from 3.3).

## 3.3 (build 104, 2026-10-13)
- Tests trimmed to behaviour, not layout: AppearanceChecks no longer pins drawer membership or
  order (owner rules live in AGENTS.md); InteractionRegressionChecks no longer pins default
  widgets, dock order, Settings page order/titles or pixel sizes; check-window no longer covers
  HiddenApps; check-incoming-messages also fails if any `sqlite3_open` lacks
  `SQLITE_OPEN_READONLY`.
- Updater: trusted download hosts and codesign TeamIdentifier parsing moved from UpdateService
  into `ReleaseRevision.isTrustedDownload` / `signingTeam(fromCodesignOutput:)` and are covered
  by check-update-revisions; an empty `TeamIdentifier=` line no longer parses as a team.
- Stickers' glow is a radial gradient instead of a blurred disc (softer, cheaper, identical in
  offscreen captures).
- Docs consolidated: AGENTS.md rewritten by area with a Standing rules list; BUILD-STATUS.md
  became this changelog; FEATURE-AUDIT.md, feature-audit.json and docs/PROJECT_GUIDE.md removed.

## 3.2 (build 103, 2026-10-12)
- Clock page: with labels drawn, the large readout shows only for a dropped pin (it covered the
  map and hover card); a saved place in this Mac's zone is the current place
  (`WidgetOptions.isCurrent`: accent pin and chip, no duplicate local pin).
- Website captures: shared `WebsiteDemoNotch.siteDock` (nine apps plus Home); the Music reel
  became one native-60 fps `music-showcase` (songs in matching Nature themes with lyric
  excerpts, `MACSPACES_DEMO_TRACKS`); `readme-hero` for the README; the converter reel's
  pointer drives the lit wedge.
- `Scripts/publish-docs.sh` publishes README/Demos-only updates without a new installer.

## 3.1 (build 102, 2026-10-12)
- Rainbow drawn as a smooth flowing colour field (`rainbowFlow`) instead of ribbons.
- Sky order fixed: Starlight, Aurora, Plasma, Nebula, Prism (owner).
- Settings → Updates shows only the version (build on hover); System memory shows used only.
- Codex's website demo-clip debug changes.

## 3.0 (build 101, 2026-10-12)
- Everything since 2.99 (2.100 was pushed but never released). Versions after 2.x are plain
  names (owner); check-release-policy only requires the build to keep rising.
- Theme photos converted to HEIC q85 (57 MB → 6 MB, visually identical). Rainbow drawn
  (`rainbowCurrent`), its keyboard photo dropped; Prism keeps its photo with a slow hue
  rotation; Aurora is its photo with the flowing shader (owner: no animation layered on top).
- Clock search adds Apple geocoding for any town or address, saved as named places
  (`zone#Name#lat,lon`); dropped pins keep their own name.
- Menu-bar menu slimmed: no Dictation or Meeting Controls (owner).
- System stats card laid out for the real page width.

## 2.100 (build 100, 2026-10-12, not released; shipped in 3.0)
- System page (owner): `SystemStatsWidget(detailed:)` (network, swap, memory GB, free disk,
  load, uptime, thermal) and `OvertimeCard` (Low battery, Agents keep running via
  `LidClosedAwake`/`pmset disablesleep`, Keep awake).
- Privileged power helper `MacSpacesPowerHelper` (SMAppService daemon, two-call XPC contract,
  client signing requirement, no sudoers); packaging signs it; `check-power-helper` added.
- Clock: Map style (`MapClock`, `ClockGeography`), redesigned Dot (`DotTime`), Clock page
  (`NotchTab.clock`, appended once to saved docks) with hover readout, reverse geocoding, ±12 h
  scrubber and place search; up to six places.
- No boxed widgets or page cards (owner: "no blocks"); the Media tile's artwork wash removed.
- Flower themes draw background images with the FloralBreeze shader.
- Theme effect toggles removed (owner); lyric motion honours the app's Reduce Motion.
- Settings reorganized (owner): Activities became Notch (every show/hide setting plus Dock), new
  Files page, Motion moved to Appearance, Keep history after quitting moved to Clipboard;
  check-settings-search covers seven destinations.
- CI builds Debug (arm64).

## 2.99 (build 99, 2026-10-12)
- Glass presets redone (owner: they all looked like frost, Bronze looked bad): Smoke fixed dark,
  Frost fixed white, Glass a neutral pane, Tinted titled Custom with a neutral slate default;
  `nookForeground` honours `fixedScheme`; cards draw a Canvas stand-in desktop.
- `Scripts/ship.sh` runs the whole release; CI builds arm64 only with cached packages and
  cancels superseded runs.

## 2.98 (build 98, 2026-10-12)
- Drawer order Core, Terminal, Nature, Tech, Glass (owner). Nature lists one row of five per
  former drawer, each by colour. Bronze replaced by Tinted (`TintedGlassColors`: tint, accent,
  strength, blur); a saved "bronze" opens as Tinted.

## 2.97 (build 97, 2026-10-12)
- Owner corrections to 2.96: MacSpaces uses the Noir palette (the owner said "Noir", heard as
  "Nord"); `.nord` restored in Terminal. Rainbow back in Tech; Hologram removed (saved →
  Rainbow); Bronze glass theme added; Bloom, Forest, Earth, Water and Sky merged into Nature.
  Clear is fully transparent.

## 2.96 (build 96, 2026-10-12)
- Themes regrouped (owner): the old MacSpaces blue became Midnight in Terminal; new Glass drawer
  (`glassTint`, `NookBackdrop`: Liquid Glass on macOS 26+, a behind-window blur before);
  Turquoise added; a Hologram scene (rejected in 2.97).

## 2.95 (build 95, 2026-10-11)
- App icon changed to the notch moon (owner pick from solid marks in the style of Kuwayama's
  *Trademarks & Symbols* vol. 2; the "//" slashes and an outlined alcove were dropped).

## 2.94 (build 94, 2026-10-11)
- Cleanup, behaviour unchanged: ~1,040 unreferenced lines removed; `FeatureCatalog` trimmed to
  shipped features (16 never-built entries, `FeatureSurface`, `FeatureAvailability` gone);
  `ContactNames` on `OSAllocatedUnfairLock`; `TimerService` in `.common` modes; shared
  `WidgetOptions.Keys`.
- Legacy theme engine removed (owner): ThemeStore 846 → ~200 lines; ThemePreset, AccentChoice,
  ThemeSurface and WidgetVisualStyle gone; legacy preset ids migrate once via
  `ThemeFamily(legacy:)`; old custom colours are not carried over; per-widget styles removed.

## 2.93 (build 93, 2026-10-11)
- The closed notch no longer shows coding agents (owner): `CollapsedActivityKind.agent`, the
  agent notch views and the vendored ThinkingOrbs removed. Agents tab and needs-you cards stay.
- README reworked: Title Case, plain requirements line, HTML image rows, no Rainbow shot.

## 2.92 (build 92, 2026-10-11)
- macOS 13+ (was 15+): macOS 14/15 SwiftUI APIs go through `OlderMacOS.swift`; EventKit access
  checked with `#available`; notification banners use the older db2 path before macOS 15.
- 1.14 retired: `main` is a single root commit; v1.14 and v2.33–v2.91 tags and releases deleted.
  README rewritten around the website's captures; the Homebrew cask requires :ventura.

## 2.91 (build 91, 2026-10-09)
- LRCLIB records with missing/null duration accepted; malformed records skipped individually.
- Meetings and Dictation became Nook pages (standalone windows removed), appended once to saved
  docks; Dictation stops when left and pastes to the captured app.

## 2.90 (build 90, 2026-10-08)
- `SpotifyCovers`: Spotify's distributed notification triggers an immediate refresh and an
  oEmbed cover (300 then 640 px); `ArtworkLookup` delayed 1.2 s, once per track.

## 2.89 (build 89, 2026-10-08)
- `ArtworkLookup` fills missing covers from iTunes then Deezer, only on an artist and
  album/title match.

## 2.87–2.88
- No record kept.

## 2.86
- Settings search: a local static index of destinations, cards, keywords and permission rows;
  ⌘F, arrows, Return and Escape; results open the destination at a stable anchor.

## 2.85
- Closed-notch activity lanes measured independently with the surface shifted around a centred
  camera (agent grouping in the notch later removed in 2.93).

## 2.84
- Coding-agent live activities with host icons and stable ordering (removed from the notch in 2.93).

## 2.83 (build 83, 2026-10-07)
- AppKit-owned Nook content container isolates SwiftUI window resizing (an intermittent
  layout-limit crash); window checks cover host containment and 120 size transitions.
- Dock: Home joins the app-pages capsule; the middle capsule holds active-page controls; the
  last holds Settings with optional Pin and Close.

## 2.82 (build 82, 2026-10-07)
- Usability review: Find Action (⌃⌥Space) over MacSpaces actions and Shortcuts, page shortcuts,
  keyboard pinning; shared File Tools with staged, collision-safe, cancellable jobs and presets;
  Tray multi-selection, preview, undo, offline references and damaged-list recovery; App
  Intents and Finder Services; opt-in completed-file folder watching; on-device dictation;
  guarded Zoom/Google Meet controls; Music playlist order. Spotify Web API sign-in excluded.
- Validation: check-file-tools; FeatureQA review-regressions and review-tools.

## 2.81 (build 81, 2026-10-06)
- Coding projects named by repository (worktrees and Orca workspaces stripped); `<synthetic>`
  skipped; Usage shows 4 projects and 3 models.

## 2.80 (build 80, 2026-10-06)
- Notifications open their page when it's in the dock (Messages chat, Terminal Agents tab);
  cards fall back otherwise and are sized to their content. Notarization waits up to 60 min.

## 2.79 (build 79, 2026-10-06)
- Converter wheel centre is a `FileGlyph`; QuickLook thumbnails dropped.

## 2.78 (build 78, 2026-10-06)
- Lanes pad 10 pt on the outer edge and 4 pt beside the camera; minimum 36 pt.

## 2.77 (build 77, 2026-10-06)
- Closed-notch lanes measured to fit their content (`LaneWidthKey`), except power and system.

## 2.76 (build 76, 2026-10-06)
- Fixes from the 2.75 engineering audit: per-chat drafts and inbox sessions, `ProtectedFile`,
  on-device-only voice following, Maccy import filters, `FocusSilencing`, Codex cumulative-total
  dedupe and a 14-day window, `HiddenApps` at window build.

## 2.75 (build 75, 2026-10-05)
- Toggles for the paste-queue count and screenshot thumbnail in the closed notch.

## 2.74 (build 74, 2026-10-05)
- Agent pulse rendering fix (removed in 2.93).

## 2.73 (build 73, 2026-10-05)
- Messages thread: reactions folded onto messages, attachments (images inline); Hide and Delete
  through Messages' own confirmation.

## 2.72 (build 72, 2026-10-05)
- Themes regrouped (Core, Terminal, Bloom, Forest, Earth, Water, Sky, Tech); new palettes and
  scenes, several retired via `ThemeFamily.replaced`; ThemeMotif rebuilt as one effect per scene.
- Messages show Contacts photos.

## 2.71 (build 71, 2026-10-05)
- Stickers chosen by a vote across the line's words, then `NLEmbedding` meaning (0.88 cutoff).

## 2.70 (build 70, 2026-10-05)
- World Clock merged into Clock (Regular/Dot styles, places); `libraryGroups` must list every widget.

## 2.69 (build 69, 2026-10-05)
- Messages page (read-only inbox and thread) with verified replies; needs-you agent cards.

## 2.68 (build 68, 2026-10-05)
- World Clock widget (merged into Clock in 2.70).

## 2.67 (build 67, 2026-10-05)
- Contacts names for Messages (`ContactNames`); GitHub streaks and stats; Usage ranks projects and models.

## 2.66 (build 66, 2026-10-05)
- Agent hook adds PreToolUse and payload snippets; installs upgraded on launch; Terminal page
  Agents tab.

## 2.65 (build 65, 2026-10-05)
- Lyrics match across scripts and restore censored words from lyrics.ovh; 92 stickers with
  natural colours.

## 2.64 (build 64, 2026-10-05)
- 47 stickers with depth; `Globe`; spins by scaling instead of rotation3DEffect.

## 2.63 (build 63, 2026-10-05)
- Fresh-install Home and dock defaults (`starterSizes`, `defaultDock`, `legacyDock`); the Home
  lyrics bar removed; dock reordering by drag handle.

## 2.62 (build 62, 2026-10-05)
- Timer lane measured in its rounded font; times never wrap.

## 2.61 (build 61, 2026-10-05)
- Per-slot timer colours; stickers beside the poster, never over it.

## 2.60 (build 60, 2026-10-05)
- `SecureStorage` (Secure Enclave-derived AES-GCM for kept history, pins, scripts); sticker
  scenes; Terminal page as one tab bar.

## 2.59 (build 59, 2026-10-05)
- Restructure: Home widgets and pages are one feature (`NookWidgetKind.page`, anchored page
  transition, shared `ClipListRow`/`ClipMenu`). Released alone so 2.58 was the rollback point.

## 2.58 (build 58, 2026-10-05)
- Lyric styles Stickers, Karaoke and Typewriter; Focus timer Do Not Disturb via named Shortcuts;
  Settings content under the title bar; coding column tabs.

## 2.57 (build 57, 2026-10-05)
- Terminal page coding panel (`CodingStats`: Claude Code and Codex logs, rate limits, GitHub
  contributions, dev servers).

## 2.56 (build 56, 2026-10-05)
- Clipboard parity with Supaste/Maccy: OCR text, @/# filters, snippets, collections,
  auto-delete, case styles, pin keys, drag out, colour picker, Maccy import. Timers back to up
  to three slots; Bluetooth outputs; converter Under 1 MB; PDF→TXT removed.

## 2.55 (build 55, 2026-10-05)
- Teleprompter; notch banners for Messages and opt-in notifications; Messages widget;
  screenshots to Tray with Copy Text; Luhn/.env credential filter; resizable Settings.

## 2.54 (build 54, 2026-10-05)
- Meeting countdown, coding-agent activity hook, audio output menu, Tray/basket AirDrop, hide in
  chosen apps, Calculator and Dev Servers widgets; check-calculator.

## 2.53 (build 53, 2026-10-05)
- Maccy-style clipboard popup (⇧⌘C) and Settings → Clipboard.

## 2.52 (build 52, 2026-10-04)
- Timed intros and instrumental breaks clear the lyric.

## 2.51 (build 51, 2026-10-04)
- Tray page basket chips; basket fold restores its circle; Remove Basket submenu.

## 2.50 (build 50, 2026-10-04)
- Paste queue; `ClipboardSecrets`; stricter LRCLIB scoring; converter wheel hit-test fix.

## 2.49 (build 49, 2026-10-04)
- File Converter wheel; file baskets; slimmer menu; website demo renderer.

## 2.48 (build 48, 2026-10-03)
- Poster lyric layout fixes.

## 2.47 (build 47, 2026-10-03)
- Lyric sync on one clock (`estimatedElapsed`, 0.25 s lead); styles trimmed to Classic, Poster,
  Choreography (2.46's Stanza stage, Waterformed and Psychedelic bloom read back as Classic);
  Pulse theme → Fireworks.

## 2.46 (build 46, 2026-10-03)
- Lyric styles; Terminal, Shortcuts and Mirror pages; Nook closes for Mission Control; Audio
  (per-app volume) widget and its Core Audio engine removed.

## 2.45 (build 45, 2026-10-03)
- Terminal widget (SwiftTerm); `lingeringTabs`; CI checks and build in parallel; Mission
  Control guard for hover and scroll.

## 2.44 (build 44, 2026-10-03)
- Review fixes for widget undo and key handling; website Home still mode.

## 2.43 (build 43, 2026-10-02)
- Tsukumo removed at the owner's request (page, bridge, transport, checks); the Coding page
  removed. The Tsukumo colour theme stays.

## 2.42 (build 42, 2026-10-02)
- Home widget headers removed; click-to-select with Delete and Undo; per-profile dock buttons;
  `RefreshButton`.

## 2.41 (build 41, 2026-10-02)
- Volume and brightness feedback removed (macOS shows its own); `.periodic` TimelineViews.

## 2.40 (build 40, 2026-09-30)
- Tsukumo page (removed in 2.43).

## 2.39 (build 39, 2026-09-30)
- Live and Minimal theme drawers; animated scene effects at up to 30 fps only while open.

## 2.38 (build 38, 2026-09-30)
- Theme drawers and patterns; Karma replaces One Dark; `MacSpacesDevelopmentBuild` removed, so
  2.x reads releases/latest.

## 2.37 (build 37, 2026-09-30)
- macOS 15 and universal; Icon Composer app icon; updater rejects builds this Mac can't run.
  Made official (Latest) the same day; 1.14 stayed for macOS 13–14 until 2.92.

## 2.36 (build 36, 2026-09-30)
- 2.x updates itself (reads the release list, newest of its major version).

## 2.35 (build 35, 2026-09-30)
- New themes, opt-in low-battery agent alert, IOKit battery details, notch equalizer.

## 2.34 (build 34, 2026-09-29)
- Music page about 15% smaller. Pre-release.

## 2.33 (2026-09-28)
- Music, Weather and Calendar pages; configurable dock.

## 2.32 (2026-09-28)
- Version became major.build; Home widget sizes; widget upgrades; Settings Widgets editor.

## 2.0 development (builds 15–32, 2026-09-27 – 09-28)
- Dependency-ordered service lifecycle, shared action registry and feature metadata.
- Stationary Nook window policy and AppKit-owned geometry (fixes a recursive resize crash).
- Rich clipboard, multiple notes, file baskets, Messages adapter and read-only incoming reader.
- Branded DMG installer; detached dock; camera clearance; Permissions page; Music page layouts.

## 1.0.0 (builds 12–14, 2026-09-27)
- Stationary window policy and window-size stability fixes; Homebrew cask.
