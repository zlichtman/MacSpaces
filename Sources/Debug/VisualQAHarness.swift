#if DEBUG
import SwiftUI
import AppKit

/// Opt-in offscreen rendering for deterministic visual inspection in CI and
/// local development. Run with MACSPACES_VISUAL_QA=1; Release builds omit it.
@MainActor
enum VisualQAHarness {
    static func captureIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["MACSPACES_VISUAL_QA"] == "1" else {
            return false
        }

        let outputDirectory = URL(fileURLWithPath: "/private/tmp/macspaces-visual-qa", isDirectory: true)
        let readmeDirectory = URL(
            fileURLWithPath: "/private/tmp/macspaces-readme-candidates",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: readmeDirectory,
            withIntermediateDirectories: true
        )

        // Public-facing captures always use the shipped visual identity, then
        // restore the user's complete defaults domain before the harness exits.
        let defaults = UserDefaults.standard
        let defaultsDomainName = Bundle.main.bundleIdentifier ?? "dev.opensource.MacSpaces"
        let previousDefaultsDomain = defaults.persistentDomain(forName: defaultsDomainName)
        ThemeStore.shared.reset()
        precondition(ThemeStore.shared.glowStrength == 0)
        precondition(ThemeStore.shared.notchGlowStrength == 0)
        precondition(ThemeStore.shared.dockGlowStrength == 0)

        SettingsNavigationModel.shared.selection = .notch
        render(
            SettingsView()
                .frame(width: 900, height: 640),
            size: CGSize(width: 900, height: 640),
            to: outputDirectory.appendingPathComponent("settings.png")
        )

        SettingsNavigationModel.shared.selection = .notch
        render(
            SettingsView()
                .frame(width: 900, height: 640),
            size: CGSize(width: 900, height: 640),
            to: outputDirectory.appendingPathComponent("nook-settings.png")
        )
        render(
            SettingsView()
                .frame(width: 900, height: 640),
            size: CGSize(width: 900, height: 640),
            to: readmeDirectory.appendingPathComponent("04-appearance.png")
        )
        render(
            SettingsView()
                .frame(width: 1000, height: 1050),
            size: CGSize(width: 1000, height: 1050),
            to: outputDirectory.appendingPathComponent("nook-widget-builder.png")
        )

        SettingsNavigationModel.shared.selection = .dock
        render(
            SettingsView()
                .frame(width: 900, height: 640),
            size: CGSize(width: 900, height: 640),
            to: outputDirectory.appendingPathComponent("dock-settings.png")
        )

        SettingsNavigationModel.shared.selection = .dock
        render(
            SettingsView()
                .frame(width: 900, height: 640),
            size: CGSize(width: 900, height: 640),
            to: outputDirectory.appendingPathComponent("themes.png")
        )

        let connectedDisplayIDs = DisplayTargeting.connectedDisplays.map(\.id)
        render(
            VStack(alignment: .leading, spacing: 12) {
                Text("Displays")
                    .font(.headline)
                DisplayTargetPicker(
                    mode: .constant(.selected),
                    selectedIDs: .constant(connectedDisplayIDs),
                    preferBuiltIn: true
                )
            }
            .padding(20)
            .frame(width: 520, height: 210, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor)),
            size: CGSize(width: 520, height: 210),
            to: outputDirectory.appendingPathComponent("display-targeting.png")
        )

        let services = AppServices.shared
        let previousNowPlaying = services.nowPlaying.info
        let previousNookProfiles = NookSettings.shared.profiles
        let previousNookProfileID = NookSettings.shared.activeProfileID
        let previousMusicActivity = NookSettings.shared.showMusicLiveActivity
        let previousTimerActivity = NookSettings.shared.showTimerLiveActivity
        let previousBluetoothActivity = NookSettings.shared.showBluetoothLiveActivity
        let previousPowerActivity = NookSettings.shared.showPowerLiveActivity
        let previousTeleprompter = NookSettings.shared.showTeleprompterBar
        let previousExpandedWidth = NookSettings.shared.expandedWidth
        let previousFitWidthToProfile = NookSettings.shared.fitWidthToProfile
        ThemeStore.shared.setPreset(.catppuccinMocha, for: .notch)
        ThemeStore.shared.customAccentHex = "#CBA6F7"
        ThemeStore.shared.accentChoice = .custom
        let previewProfile = NookProfile(
            id: UUID(),
            name: "Visual QA",
            widgets: [.media, .timer, .clock],
            widgetWidths: [
                NookWidgetKind.media.rawValue: 260,
                NookWidgetKind.timer.rawValue: 116,
                NookWidgetKind.clock.rawValue: 116,
            ],
            widgetStyles: [
                NookWidgetKind.media.rawValue: .studio,
                NookWidgetKind.timer.rawValue: .studio,
                NookWidgetKind.clock.rawValue: .studio,
            ]
        )
        NookSettings.shared.profiles = [previewProfile]
        NookSettings.shared.activeProfileID = previewProfile.id
        NookSettings.shared.expandedWidth = 860
        NookSettings.shared.fitWidthToProfile = true

        // Interaction regression: transient ordering is committed atomically,
        // compact pairs preserve their members, and a cancelled drag cannot
        // leave persistence suspended.
        NookSettings.shared.beginInteractiveReorder()
        NookSettings.shared.setWidgetOrder([.timer, .clock, .media])
        precondition(NookSettings.shared.widgets == [.timer, .clock, .media])
        precondition(
            NookSettings.shared.widgets.nookLayoutItems().first?.kinds
                == [.timer, .clock]
        )
        NookSettings.shared.cancelInteractiveReorder()
        precondition(!NookSettings.shared.isInteractiveReorderActive)
        NookSettings.shared.widgets = [.media, .timer, .clock]

        var previewTrack = NowPlayingInfo()
        previewTrack.title = "I Melt With You"
        previewTrack.artist = "Modern English"
        previewTrack.album = "Pillow Lips"
        previewTrack.isPlaying = true
        previewTrack.duration = 235.933
        previewTrack.elapsed = 96
        previewTrack.artwork = NSImage(
            contentsOfFile: "/private/tmp/macspaces-readme-candidates/i-melt-with-you.jpg"
        ) ?? previewArtwork()
        services.nowPlaying.setPreviewInfo(previewTrack)
        NookSettings.shared.showMusicLiveActivity = true
        NookSettings.shared.showTimerLiveActivity = false
        NookSettings.shared.showBluetoothLiveActivity = false
        NookSettings.shared.showPowerLiveActivity = false
        NookSettings.shared.showTeleprompterBar = false

        let previewShelf = ShelfStore()
        previewShelf.setPreviewItems(
            [
                URL(fileURLWithPath: "/Applications/MacSpaces.app"),
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("README.md"),
                URL(fileURLWithPath: "/private/tmp/macspaces-readme-candidates/Cover.jpg"),
            ],
            selectedIndex: 0
        )
        let previewTimer = TimerService(
            previewRemaining: 18 * 60 + 19,
            total: 25 * 60
        )
        let nookModel = NotchViewModel(
            geometry: .synthetic,
            availableWidth: 1440,
            settings: .shared,
            shelf: previewShelf,
            nowPlaying: services.nowPlaying,
            powerMonitor: services.powerMonitor,
            timerService: previewTimer,
            bluetoothMonitor: services.bluetooth,
            systemActivityMonitor: services.systemActivity,
            teleprompter: services.teleprompter
        )
        nookModel.state = .expanded
        render(
            NotchContainerView(viewModel: nookModel)
                .frame(width: 1040, height: 280)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 1040, height: 280),
            to: outputDirectory.appendingPathComponent("nook.png")
        )
        render(
            NotchContainerView(viewModel: nookModel)
                .frame(width: 840, height: 280)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 840, height: 280),
            to: readmeDirectory.appendingPathComponent("01-nook.png")
        )

        services.teleprompter.setPreview(
            current: "I'll stop the world and melt with you",
            upcoming: "You've seen the difference and it's getting better all the time",
            source: .lyrics
        )
        NookSettings.shared.showTeleprompterBar = true
        render(
            NotchContainerView(viewModel: nookModel)
                .frame(width: 1040, height: 330)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 1040, height: 330),
            to: outputDirectory.appendingPathComponent("nook-teleprompter.png")
        )
        NookSettings.shared.showTeleprompterBar = false

        NookSettings.shared.expandedWidth = 900
        NookSettings.shared.fitWidthToProfile = false
        nookModel.selectedTab = .tray
        nookModel.isDropTargeted = true
        render(
            NotchContainerView(viewModel: nookModel)
                .frame(width: 1040, height: 280)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 1040, height: 280),
            to: readmeDirectory.appendingPathComponent("05-file-trap.png")
        )
        nookModel.selectedTab = .nook
        nookModel.isDropTargeted = false
        NookSettings.shared.expandedWidth = 860
        NookSettings.shared.fitWidthToProfile = true

        nookModel.state = .collapsed
        render(
            NotchContainerView(viewModel: nookModel)
                .frame(width: 420, height: 64)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 420, height: 64),
            to: outputDirectory.appendingPathComponent("compact-music.png")
        )

        let stackedModel = NotchViewModel(
            geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true),
            availableWidth: 1440,
            settings: .shared,
            shelf: ShelfStore(),
            nowPlaying: services.nowPlaying,
            powerMonitor: services.powerMonitor,
            timerService: TimerService(previewRemaining: 19 * 60 + 48, total: 25 * 60),
            bluetoothMonitor: services.bluetooth,
            systemActivityMonitor: services.systemActivity,
            teleprompter: services.teleprompter
        )
        NookSettings.shared.showTimerLiveActivity = true
        render(
            NotchContainerView(viewModel: stackedModel)
                .frame(width: 520, height: 66)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 520, height: 66),
            to: outputDirectory.appendingPathComponent("compact-timer-music.png")
        )
        render(
            NotchContainerView(viewModel: stackedModel)
                .frame(width: 520, height: 66)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 520, height: 66),
            to: readmeDirectory.appendingPathComponent("02-live-activities.png")
        )

        let previewBluetooth = BluetoothMonitor()
        previewBluetooth.setPreviewChange(
            deviceName: "Zach's AirPods Pro",
            batteryPercent: 82
        )
        NookSettings.shared.showMusicLiveActivity = false
        NookSettings.shared.showTimerLiveActivity = false
        NookSettings.shared.showBluetoothLiveActivity = true
        let bluetoothModel = NotchViewModel(
            geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true),
            availableWidth: 1440,
            settings: .shared,
            shelf: ShelfStore(),
            nowPlaying: services.nowPlaying,
            powerMonitor: services.powerMonitor,
            timerService: services.timerService,
            bluetoothMonitor: previewBluetooth,
            systemActivityMonitor: services.systemActivity,
            teleprompter: services.teleprompter
        )
        render(
            NotchContainerView(viewModel: bluetoothModel)
                .frame(width: 520, height: 66)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 520, height: 66),
            to: outputDirectory.appendingPathComponent("compact-bluetooth-name.png")
        )
        NookSettings.shared.showMusicLiveActivity = true
        render(
            NotchContainerView(viewModel: bluetoothModel)
                .frame(width: 600, height: 66)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 600, height: 66),
            to: outputDirectory.appendingPathComponent("compact-bluetooth-music.png")
        )

        let previewSystemActivity = SystemActivityMonitor()
        previewSystemActivity.setPreviewActivity(
            SystemLiveActivity(
                kind: .volume,
                label: "62%",
                systemImage: "speaker.wave.2.fill",
                level: 0.62
            )
        )
        NookSettings.shared.showMusicLiveActivity = false
        let systemActivityModel = NotchViewModel(
            geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true),
            availableWidth: 1440,
            settings: .shared,
            shelf: ShelfStore(),
            nowPlaying: services.nowPlaying,
            powerMonitor: services.powerMonitor,
            timerService: services.timerService,
            bluetoothMonitor: services.bluetooth,
            systemActivityMonitor: previewSystemActivity,
            teleprompter: services.teleprompter
        )
        render(
            NotchContainerView(viewModel: systemActivityModel)
                .frame(width: 520, height: 66)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 520, height: 66),
            to: outputDirectory.appendingPathComponent("compact-system-activity.png")
        )
        NookSettings.shared.showMusicLiveActivity = true
        nookModel.state = .expanded
        let previewNookWidgets = NookSettings.shared.widgets
        NookSettings.shared.widgets = []
        render(
            NotchContainerView(viewModel: nookModel)
                .frame(width: 520, height: 220)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 520, height: 220),
            to: outputDirectory.appendingPathComponent("nook-empty.png")
        )
        NookSettings.shared.widgets = previewNookWidgets

        let dockStore = DockStore.shared
        let previousDockProfiles = dockStore.profiles
        let previousDockProfileID = dockStore.activeProfileID
        let previousPosition = dockStore.position
        let previousTileSize = dockStore.tileSize
        let previousSideDockWidth = dockStore.sideDockWidth
        let previewDockID = UUID()
        let previewPomodoro = WidgetInstance(kind: .pomodoro)
        let previewClock = WidgetInstance(kind: .clock)
        let previewWeather = WidgetInstance(kind: .weather)
        let previewSecondClock = WidgetInstance(kind: .clock)
        dockStore.beginInteractiveReorder()
        dockStore.profiles = [
            DockProfile(
                id: previewDockID,
                name: "Visual QA",
                widgets: [
                    WidgetInstance(kind: .nowPlaying),
                    previewPomodoro,
                    previewClock,
                    previewWeather,
                    previewSecondClock,
                    WidgetInstance(kind: .calendar),
                    WidgetInstance(kind: .quickActions),
                ]
            )
        ]
        dockStore.activeProfileID = previewDockID
        dockStore.tileSize = 96

        // Dock interaction regression: the rendered order is committed once
        // on release without replacing any per-widget appearance or sizing.
        let configuredClock = WidgetInstance(
            kind: .clock,
            visualStyle: .terminal,
            sizeMode: .full
        )
        let pairedWeather = WidgetInstance(
            kind: .weather,
            visualStyle: .glass,
            sizeMode: .compact
        )
        let pairedTimer = WidgetInstance(
            kind: .pomodoro,
            visualStyle: .orbit,
            sizeMode: .automatic
        )
        dockStore.widgets = [configuredClock, pairedWeather, pairedTimer]
        precondition(
            dockStore.widgets.dockLayoutItems(vertical: false).count == 2
        )
        dockStore.beginInteractiveReorder()
        dockStore.setWidgetOrder([pairedTimer, pairedWeather, configuredClock])
        dockStore.endInteractiveReorder()
        precondition(dockStore.widgets.map(\.id) == [
            pairedTimer.id,
            pairedWeather.id,
            configuredClock.id,
        ])
        precondition(
            dockStore.widgets.first(where: { $0.id == configuredClock.id })?
                .visualStyle == .terminal
        )
        precondition(
            dockStore.widgets.first(where: { $0.id == configuredClock.id })?
                .sizeMode == .full
        )
        precondition(
            dockStore.widgets.dockLayoutItems(vertical: false).count == 2
        )
        dockStore.widgets = [
            WidgetInstance(kind: .nowPlaying),
            previewPomodoro,
            previewClock,
            previewWeather,
            previewSecondClock,
            WidgetInstance(kind: .calendar),
            WidgetInstance(kind: .quickActions),
        ]

        dockStore.position = .bottom
        render(
            DockContainerView(store: dockStore)
                .frame(width: 1050, height: 130)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 1050, height: 130),
            to: outputDirectory.appendingPathComponent("dock.png")
        )
        render(
            DockContainerView(store: dockStore)
                .frame(width: 640, height: 152)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 640, height: 152),
            to: readmeDirectory.appendingPathComponent("03-dock.png")
        )

        dockStore.move(previewClock, offset: -1)
        precondition(dockStore.widgets[1].id == previewClock.id)
        render(
            DockContainerView(store: dockStore)
                .frame(width: 1050, height: 130)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 1050, height: 130),
            to: outputDirectory.appendingPathComponent("dock-compact-swapped.png")
        )
        dockStore.move(previewClock, offset: 1)
        dockStore.move(previewClock, offset: 2)
        precondition(dockStore.widgets[4].id == previewClock.id)
        dockStore.move(previewClock, offset: -2)

        let previewDockWidgets = dockStore.widgets
        dockStore.widgets = []
        render(
            DockContainerView(store: dockStore)
                .frame(width: 110, height: 130)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 110, height: 130),
            to: outputDirectory.appendingPathComponent("dock-empty.png")
        )
        dockStore.widgets = previewDockWidgets

        dockStore.position = .right
        dockStore.sideDockWidth = 150
        render(
            DockContainerView(store: dockStore)
                .frame(width: 170, height: 640)
                .background(Color(red: 0.18, green: 0.22, blue: 0.30)),
            size: CGSize(width: 170, height: 640),
            to: outputDirectory.appendingPathComponent("side-dock.png")
        )

        let mixer = AudioMixerService()
        let appURLs = [
            "/System/Applications/Music.app",
            "/Applications/Safari.app",
            "/Applications/Spotify.app",
        ]
        let mixerNames = ["Music", "Safari", "Spotify"]
        mixer.setPreview(
            sessions: mixerNames.enumerated().map { index, name in
                let url = URL(fileURLWithPath: appURLs[index])
                return AppAudioSession(
                    id: "preview.\(name.lowercased())",
                    name: name,
                    icon: NSWorkspace.shared.icon(forFile: url.path),
                    processObjectIDs: [],
                    isProducingAudio: index != 1,
                    volume: [0.36, 1.0, 0.72][index],
                    level: [0.66, 0.0, 0.42][index]
                )
            }
        )
        render(
            AudioMixerPanel(mixer: mixer)
                .frame(width: 430, height: 500),
            size: CGSize(width: 430, height: 500),
            to: outputDirectory.appendingPathComponent("app-mixer.png")
        )

        dockStore.profiles = previousDockProfiles
        dockStore.activeProfileID = previousDockProfileID
        dockStore.position = previousPosition
        dockStore.tileSize = previousTileSize
        dockStore.sideDockWidth = previousSideDockWidth
        dockStore.cancelInteractiveReorder()
        precondition(!dockStore.isInteractiveReorderActive)
        dockStore.flushPersistence()
        services.nowPlaying.setPreviewInfo(previousNowPlaying)
        NookSettings.shared.profiles = previousNookProfiles
        NookSettings.shared.activeProfileID = previousNookProfileID
        NookSettings.shared.showMusicLiveActivity = previousMusicActivity
        NookSettings.shared.showTimerLiveActivity = previousTimerActivity
        NookSettings.shared.showBluetoothLiveActivity = previousBluetoothActivity
        NookSettings.shared.showPowerLiveActivity = previousPowerActivity
        NookSettings.shared.showTeleprompterBar = previousTeleprompter
        NookSettings.shared.expandedWidth = previousExpandedWidth
        NookSettings.shared.fitWidthToProfile = previousFitWidthToProfile
        if let previousDefaultsDomain {
            defaults.setPersistentDomain(previousDefaultsDomain, forName: defaultsDomainName)
        } else {
            defaults.removePersistentDomain(forName: defaultsDomainName)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.terminate(nil)
        }
        return true
    }

    private static func render<Content: View>(
        _ content: Content,
        size: CGSize,
        to url: URL
    ) {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func previewArtwork() -> NSImage {
        NSImage(size: NSSize(width: 160, height: 160), flipped: false) { rect in
            NSGradient(colors: [
                NSColor(red: 0.06, green: 0.10, blue: 0.18, alpha: 1),
                NSColor(red: 0.10, green: 0.90, blue: 0.65, alpha: 1),
            ])?.draw(in: rect, angle: -35)

            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 38, dy: 38), xRadius: 20, yRadius: 20)
            NSColor.black.withAlphaComponent(0.62).setFill()
            path.fill()
            return true
        }
    }
}
#endif
