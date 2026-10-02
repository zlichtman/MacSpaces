#if DEBUG
import AppKit
import SwiftUI

@MainActor enum FeatureQAHarness {
    static func captureIfRequested() -> Bool {
        guard let output = ProcessInfo.processInfo.environment["MACSPACES_FEATURE_QA"] else { return false }
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.FeatureQA")
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        InteractionRegressionChecks.run()
        DeviceRegressionChecks.run()
        let clipboard = ClipboardMonitor()
        clipboard.setPreviewEntries(["Design review at 10:30", "A small space for a clear head."])
        _ = clipboard.toggleFavorite(clipboard.entries[0])
        let audio = AudioMixerService()
        audio.setPreview(sessions: [
            AppAudioSession(id: "demo.music", name: "Music", icon: nil, processObjectIDs: [], isProducingAudio: true, volume: 0.7, level: 0.2),
            AppAudioSession(id: "demo.browser", name: "Browser", icon: nil, processObjectIDs: [], isProducingAudio: true, volume: 1, level: 0.3)
        ])
        let stats = SystemStatsService(); stats.setPreview()
        let awake = KeepAwakeService()
        for preset in [ThemePreset.midnight, .forest, .frosted] {
            ThemeStore.shared.setPreset(preset, for: .notch)
            let view = HStack(spacing: 14) {
                tile("Clipboard") { ClipboardWidget(monitor: clipboard) }
                tile("Audio Controls") { AudioControlsWidget(service: audio) }
                tile("System Stats") { SystemStatsWidget(service: stats) }
                tile("Keep Awake") { KeepAwakeWidget(service: awake) }
            }
            .padding(18)
            .background(ThemeStore.shared.notch.surfaceGradient)
            .environment(\.colorScheme, .dark)
            render(view, to: directory.appendingPathComponent("features-\(preset.rawValue).png"))
        }
        let player = NowPlayingController()
        var track = NowPlayingInfo()
        track.title = "A long track title that should wrap without hiding the playback controls"
        track.artist = "MacSpaces UI check"
        track.sourceName = "Music"
        track.capabilities = [.playPause, .previous, .next, .seek]
        track.duration = 240
        track.elapsed = 75
        track.isPlaying = true
        player.setPreviewInfo(track)
        renderMusic(player, name: "music-long-title", directory: directory)
        // The Home tile must pick its layout by width, never by title length.
        for (name, title) in [("tile-short", "Naked on the Floor"), ("tile-long", "Maps - Live at the Royal Albert Hall")] {
            track.title = title; player.setPreviewInfo(track)
            render(MediaPlayerView(nowPlaying: player, style: .studio).padding(.horizontal, 5).frame(width: 300, height: 190)
                .background(ThemeStore.shared.notch.surface).foregroundStyle(ThemeStore.shared.nookForeground)
                .environment(\.colorScheme, .dark), to: directory.appendingPathComponent("music-\(name).png"), size: NSSize(width: 300, height: 190))
        }
        track.title = "A long track title that should wrap without hiding the playback controls"
        track.duration = 0
        track.capabilities.remove(.seek)
        track.title = "Live stream"
        track.artist = "Radio"
        player.setPreviewInfo(track)
        renderMusic(player, name: "music-live", directory: directory)
        player.setPreviewInfo(NowPlayingInfo())
        renderMusic(player, name: "music-empty", directory: directory)
        let lyrics = TeleprompterService(nowPlaying: player)
        lyrics.setPreview(current: "The caption bar stays below the widgets", upcoming: "The next line stays readable", source: .lyrics)
        render(TeleprompterBarView(service: lyrics, settings: NookSettings.shared).padding(14).frame(width: 660, height: 80),
               to: directory.appendingPathComponent("music-captions.png"), size: NSSize(width: 660, height: 80))
        let fixtureFile = directory.appendingPathComponent("Fixture note.txt")
        try! Data("A synthetic file for the basket check.".utf8).write(to: fixtureFile)
        let basket = ShelfStore(basketID: UUID())
        basket.add(url: fixtureFile)
        render(ShelfView(store: basket, isDropTargeted: .constant(false)).padding(12)
            .frame(width: 500, height: 240).background(ThemeStore.shared.notch.surface),
               to: directory.appendingPathComponent("file-basket.png"), size: NSSize(width: 500, height: 240))
        render(MessagesWidget().quickActionBar().frame(width: 720, height: 38).background(ThemeStore.shared.notch.surface),
               to: directory.appendingPathComponent("messages-disconnected.png"), size: NSSize(width: 720, height: 38))
        for needsAccess in [true, false] {
            AppServices.shared.messages.setIncomingAccessPreview(needsAccess: needsAccess)
            render(MessagesWidget().receptionDetails
                .background(ThemeStore.shared.notch.surface)
                .foregroundStyle(ThemeStore.shared.nookForeground)
                .environment(\.colorScheme, .dark),
                to: directory.appendingPathComponent(needsAccess ? "messages-access.png" : "messages-listening.png"),
                size: NSSize(width: 310, height: needsAccess ? 320 : 250))
        }
        ThemeStore.shared.setPreset(.midnight, for: .notch)
        let dockSuite = "MacSpaces.DockQA." + UUID().uuidString
        let dockDefaults = UserDefaults(suiteName: dockSuite)!
        defer { dockDefaults.removePersistentDomain(forName: dockSuite) }
        let dockSettings = NookSettings(defaults: dockDefaults)
        dockSettings.widgets = [.media, .timer, .clock]
        dockSettings.showTeleprompterBar = true
        track.title = "Evening light"
        track.artist = "Sample Artist"
        track.album = "Sample Album"
        track.sourceBundleID = "com.apple.Music"
        // A synthetic cover so the artwork ambience is visible in captures.
        track.artwork = NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
            NSGradient(colors: [.systemTeal, .systemBlue, .systemPurple, .systemPink])?.draw(in: rect, angle: 35)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 190, y: 190, width: 220, height: 220)).fill()
            return true
        }
        track.duration = 240
        track.capabilities = [.playPause, .previous, .next, .seek]
        player.setPreviewInfo(track)
        for (name, width, hardware) in [("wide", CGFloat(1440), true), ("narrow", CGFloat(500), true), ("external", CGFloat(900), false)] {
            let geometry = hardware ? NotchGeometry(width: 185, height: 32, isHardwareNotch: true) : .synthetic
            let model = NotchViewModel(geometry: geometry, availableWidth: width, settings: dockSettings,
                shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
                timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
            model.state = .expanded
            precondition(model.expandedHeaderTopInset >= (hardware ? geometry.height : 0))
            precondition(model.expandedPanelSize.height + NotchViewModel.dockGap + NotchViewModel.dockHeight == model.expandedSize.height)
            let canvas = NSSize(width: model.expandedSize.width + 52, height: model.expandedSize.height + 28)
            render(NotchContainerView(viewModel: model).overlay(alignment: .top) {
                if hardware { UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(.black).frame(width: geometry.width, height: geometry.height) }
            }, to: directory.appendingPathComponent("dock-" + name + ".png"), size: canvas)
        }
        // Every Home widget, in realistic profile combinations, for design review.
        dockSettings.showTeleprompterBar = false
        AppServices.shared.systemStats.setPreview()
        AppServices.shared.calendar.setAppPreview()
        AppServices.shared.clipboard.setPreviewEntries(["Design review at 10:30", "https://github.com/zlichtman/MacSpaces", "Remember the lake photos"])
        let day: (Int, Int, Double, Double) -> WeatherSnapshot.Day = { offset, code, high, low in
            .init(date: Calendar.current.date(byAdding: .day, value: offset, to: Date())!, weatherCode: code, high: high, low: low)
        }
        let hours: [WeatherSnapshot.Hour] = (0..<12).map { offset in
            .init(date: Calendar.current.date(byAdding: .hour, value: offset, to: Date())!, weatherCode: [1, 1, 2, 3, 3, 61, 61, 3, 2, 1, 0, 0][offset],
                  temperature: [20, 21, 21, 20, 19, 17, 16, 16, 15, 15, 14, 13][offset], isDay: offset < 5, precipitationChance: [0, 0, 5, 20, 40, 70, 60, 30, 10, 0, 0, 0][offset])
        }
        AppServices.shared.weather.setPreviewSnapshot(.init(temperature: 20, weatherCode: 1, high: 22, low: 12,
            upcoming: [day(1, 0, 24, 13), day(2, 61, 18, 11), day(3, 3, 19, 10), day(4, 1, 21, 12)],
            hourly: hours, feelsLike: 19, humidity: 58, windSpeed: 12, precipitationChance: 70,
            sunrise: Date().addingTimeInterval(-36000), sunset: Date().addingTimeInterval(9000)))
        let homeProfiles: [(String, [NookWidgetKind])] = [
            ("everyday", [.media, .timer, .clock, .weather, .battery]),
            ("planning", [.calendar, .todos, .notes, .clipboard]),
            ("tools", [.shortcuts, .quickActions, .pomodoro, .keepAwake, .systemStats]),
            ("sound", [.audioControls, .mirror, .clock, .pomodoro])
        ]
        // Explicit sizes: stacked smalls of every kind next to large tiles.
        let sizedProfiles: [(String, [(NookWidgetKind, NookWidgetSize)])] = [
            ("sizes-a", [(.media, .small), (.calendar, .small), (.weather, .large), (.clock, .small), (.timer, .small)]),
            ("sizes-b", [(.calendar, .large), (.clipboard, .small), (.notes, .small), (.systemStats, .small), (.keepAwake, .small)]),
            ("sizes-c", [(.todos, .medium), (.audioControls, .small), (.pomodoro, .small), (.quickActions, .large), (.battery, .small), (.systemStats, .medium)]),
            ("sizes-running", [(.timer, .small), (.pomodoro, .small), (.clock, .small), (.battery, .small), (.media, .medium)])
        ]
        // The fixture bundle has its own defaults, so this countdown is isolated.
        AppServices.shared.timerService.start(seconds: 24 * 60 + 58)
        defer { AppServices.shared.timerService.cancel() }
        for (name, widgets) in homeProfiles + sizedProfiles.map({ ($0.0, $0.1.map(\.0)) }) {
            dockSettings.widgets = widgets
            for (kind, size) in sizedProfiles.first(where: { $0.0 == name })?.1 ?? [] { dockSettings.setSize(size, for: kind) }
            let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
                settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
                timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
            model.state = .expanded
            render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("home-" + name + ".png"),
                   size: NSSize(width: model.expandedSize.width + 52, height: model.expandedSize.height + 28))
        }
        // A file hovering over the closed notch, before the Tray opens.
        let dropModel = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
            settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
            timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
            systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
        dropModel.isDropTargeted = true
        render(NotchContainerView(viewModel: dropModel).background(Color(white: 0.55)),
               to: directory.appendingPathComponent("notch-file-drop.png"), size: NSSize(width: 420, height: 110))
        for kind in NookWidgetKind.allCases { dockSettings.setSize(kind.defaultSize, for: kind) }
        dockSettings.widgets = [.media, .timer, .clock]
        dockSettings.showTeleprompterBar = true
        AppServices.shared.codingUsage.setPreview()
        AppServices.shared.calendar.setAppPreview()
        dockSettings.dockApps = NotchTab.appPages
        for tab in [NotchTab.music, .calendar, .coding, .notes, .weather, .reminders, .timers, .clipboard, .system] {
            let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
                settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
                timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
            model.selectedTab = tab; model.state = .expanded
            render(NotchContainerView(viewModel: model).overlay(alignment: .top) {
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                        .fill(.black).frame(width: 185, height: 32)
                },
                to: directory.appendingPathComponent("app-" + tab.rawValue + ".png"),
                size: NSSize(width: model.expandedSize.width + 52, height: model.expandedSize.height + 28))
        }
        // The Tsukumo page from the spec's synthetic fixtures: Together with two bots tagged,
        // one bot with its work strip, and the review sheet.
        let agents = TsukumoAgentsClient.shared
        agents.loadPreview()
        let coder = UUID(uuidString: "6B656D6F-0000-4000-8000-000000000002")!
        let buddy = UUID(uuidString: "6B656D6F-0000-4000-8000-000000000003")!
        for (name, focused, tagged, review) in [("together", UUID?.none, [coder, buddy], false), ("bot", coder, [], false), ("review", nil, [], true)] {
            agents.setPreview(focused: focused, tagged: tagged, review: review)
            let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
                settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
                timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
            model.selectedTab = .tsukumo; model.state = .expanded
            render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("tsukumo-\(name).png"),
                   size: NSSize(width: model.expandedSize.width + 52, height: model.expandedSize.height + 28))
        }
        // Karma (2.38), dark and light, on the Music and Calendar pages.
        ThemeStore.shared.selectFamily(.karma)
        for mode in [AppearanceMode.dark, .light] {
            ThemeStore.shared.appearanceMode = mode
            for tab in [NotchTab.music, .calendar] {
                let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
                    settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
                    timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                    systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
                model.selectedTab = tab; model.state = .expanded
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("karma-\(mode.rawValue)-\(tab.rawValue).png"),
                       size: NSSize(width: model.expandedSize.width + 52, height: model.expandedSize.height + 28))
            }
        }
        ThemeStore.shared.appearanceMode = .dark
        SettingsNavigationModel.shared.selection = .appearance
        render(SettingsView(), to: directory.appendingPathComponent("settings-appearance-karma.png"), size: NSSize(width: 980, height: 1180))
        // Every drawer open, in both appearances, to review all palettes.
        NookThemePicker.startsFullyOpen = true
        ThemeStore.shared.selectFamily(.blossom)
        for mode in [AppearanceMode.dark, .light] {
            ThemeStore.shared.appearanceMode = mode
            render(SettingsView(), to: directory.appendingPathComponent("settings-themes-\(mode.rawValue).png"), size: NSSize(width: 980, height: 2150))
        }
        NookThemePicker.startsFullyOpen = false
        // Patterned themes on a real page, dark and light.
        for (family, tab) in [(ThemeFamily.blossom, NotchTab.music), (.monsoon, .calendar), (.alpine, .weather),
                              (.rainbow, .timers), (.synthwave, .music), (.codeRain, .system), (.lava, .reminders), (.firefly, .calendar)] {
            ThemeStore.shared.selectFamily(family)
            for mode in [AppearanceMode.dark, .light] {
                ThemeStore.shared.appearanceMode = mode
                let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
                    settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
                    timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                    systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
                model.selectedTab = tab; model.state = .expanded
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("motif-\(family.rawValue)-\(mode.rawValue).png"),
                       size: NSSize(width: model.expandedSize.width + 52, height: model.expandedSize.height + 28))
            }
        }
        ThemeStore.shared.appearanceMode = .dark
        ThemeStore.shared.selectFamily(.macspaces)
        // The fixture bundle has its own defaults domain, so this never touches a real profile.
        NookSettings.shared.widgets = [.media, .calendar, .weather, .clock, .timer, .notes]
        NookSettings.shared.setSize(.small, for: .media)
        NookSettings.shared.setSize(.small, for: .calendar)
        NookSettings.shared.setSize(.large, for: .weather)
        // Appearance with Custom selected, so the new row and the pickers show.
        ThemeStore.shared.customThemeBackground = "2B1E3A"; ThemeStore.shared.customThemeAccent = "FF8A5B"
        ThemeStore.shared.selectFamily(.custom)
        SettingsNavigationModel.shared.selection = .appearance
        render(SettingsView(), to: directory.appendingPathComponent("settings-appearance.png"), size: NSSize(width: 980, height: 1180))
        ThemeStore.shared.selectFamily(.macspaces)
        // Every page at the window's minimum size: nothing may push the sidebar off.
        for (label, size) in [("min", NSSize(width: 720, height: 520)), ("tiled", NSSize(width: 520, height: 480))] {
            for destination in SettingsDestination.allCases {
                SettingsNavigationModel.shared.selection = destination
                render(SettingsView().frame(width: size.width, height: size.height),
                       to: directory.appendingPathComponent("settings-\(label)-" + destination.rawValue + ".png"), size: size)
            }
        }
        for destination in [SettingsDestination.permissions, .widgets, .general] {
            SettingsNavigationModel.shared.selection = destination
            render(SettingsView(), to: directory.appendingPathComponent("settings-" + destination.rawValue + ".png"), size: NSSize(width: 980, height: 900))
        }
        print("Native feature captures and existing layout/device regressions passed.")
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }
    private static func renderMusic(_ player: NowPlayingController, name: String, directory: URL) {
        let view = MediaPlayerView(nowPlaying: player, style: .studio, largeArtwork: true)
            .frame(width: 330, height: 180)
            .background(ThemeStore.shared.notch.surface)
            .foregroundStyle(ThemeStore.shared.nookForeground)
            .environment(\.colorScheme, .dark)
        render(view, to: directory.appendingPathComponent(name + ".png"), size: NSSize(width: 330, height: 180))
    }
    private static func tile<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(12).frame(width: 240, height: 240)
            .background(ThemeStore.shared.notch.control, in: RoundedRectangle(cornerRadius: 16))
    }
    private static func render<V: View>(_ view: V, to url: URL, size: NSSize = NSSize(width: 1134, height: 276)) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; window.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        // Let entrance animations (the Nook's tile drop) settle before capture.
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
#endif
