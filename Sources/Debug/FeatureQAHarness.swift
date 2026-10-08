#if DEBUG
import AppKit
import CryptoKit
import Carbon.HIToolbox
import SwiftUI

@MainActor enum FeatureQAHarness {
    static func captureIfRequested() -> Bool {
        guard let output = ProcessInfo.processInfo.environment["MACSPACES_FEATURE_QA"] else { return false }
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.FeatureQA")
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        InteractionRegressionChecks.run()
        DeviceRegressionChecks.run()
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "dock-controls" {
            let settings = NookSettings.shared
            settings.resetToDefaults()
            settings.addProfile(named: "Focus", copyingCurrent: true)
            var track = NowPlayingInfo()
            track.title = "A synthetic song title"
            track.artist = "Sample artist"
            track.album = "Sample album"
            track.sourceName = "Music"; track.sourceBundleID = "com.apple.Music"
            track.duration = 240; track.elapsed = 75; track.isPlaying = true
            track.capabilities = [.playPause, .previous, .next, .seek]
            AppServices.shared.nowPlaying.setPreviewInfo(track)
            let model = NotchViewModel(geometry: .synthetic, availableWidth: 1440, settings: settings,
                shelf: ShelfStore.shared, nowPlaying: AppServices.shared.nowPlaying,
                powerMonitor: AppServices.shared.powerMonitor, timerService: AppServices.shared.timerService,
                bluetoothMonitor: AppServices.shared.bluetooth, systemActivityMonitor: AppServices.shared.systemActivity,
                teleprompter: AppServices.shared.teleprompter)
            model.state = .expanded; model.selectedTab = .music
            func dock(_ name: String, width: CGFloat = 572) {
                render(NotchHeaderView(viewModel: model)
                    .frame(width: width, height: 54)
                    .foregroundStyle(ThemeStore.shared.nookForeground)
                    .background(ThemeStore.shared.notch.tile),
                    to: directory.appendingPathComponent(name + ".png"), size: NSSize(width: width, height: 54))
            }
            dock("dock-music")
            track.sourceName = "Spotify"; track.sourceBundleID = "com.spotify.client"
            AppServices.shared.nowPlaying.setPreviewInfo(track)
            dock("dock-spotify")
            model.selectedTab = .nook
            dock("dock-home")
            settings.showDockPin = false; settings.showDockClose = false
            dock("dock-settings-only")
            for index in 0..<8 { settings.addProfile(named: "Profile \(index)", copyingCurrent: true) }
            dock("dock-many-profiles")
            print("Dock captures passed: Music controls, Spotify app link, Home profiles, Settings-only, many profiles")
            NSApp.terminate(nil)
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "widget-removal" {
            Task {
                await WidgetRemovalRegressionChecks.run()
                NSApp.terminate(nil)
            }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "review-regressions" {
            Task {
                do { try await ReviewRegressionChecks.run(); NSApp.terminate(nil) }
                catch { fatalError("Review check failed: " + error.localizedDescription) }
            }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "review-tools" {
            AppServices.shared.shortcuts.setPreview(["Focus On", "Send to review"])
            ThemeStore.shared.setPreset(.forest, for: .notch)
            let files = directory.appendingPathComponent("Fixture files")
            try! FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
            let urls = ["Design.md", "Budget.csv", "Unavailable.pdf"].map { files.appendingPathComponent($0) }
            for url in urls.prefix(2) { try! Data("Synthetic content".utf8).write(to: url) }
            let store = ShelfStore(basketID: UUID()); store.setPreviewItems(urls, selectedIndex: 0); store.selectAll(); store.pruneMissingItems()
            render(ShelfView(store: store, isDropTargeted: .constant(false)).background(ThemeStore.shared.notch.surface).foregroundStyle(ThemeStore.shared.nookForeground).preferredColorScheme(.dark), to: directory.appendingPathComponent("tray.png"), size: NSSize(width: 740, height: 300))
            let tools = FileToolsWindow.shared
            tools.urls = [files.appendingPathComponent("Photo.png")]
            tools.selected = FileConverter.Action(id: "preset.resize", title: "Resize or crop", symbol: "crop")
            tools.options.cropRatio = 1
            render(FileToolsView(model: tools), to: directory.appendingPathComponent("file-tools.png"), size: NSSize(width: 580, height: 620))
            let voice = DictationModel(); voice.text = "A draft captured locally. Edit it before copying or pasting."
            render(DictationView(model: voice), to: directory.appendingPathComponent("dictation.png"), size: NSSize(width: 560, height: 360))
            render(MeetingControlsView(model: MeetingControls()), to: directory.appendingPathComponent("meetings.png"), size: NSSize(width: 500, height: 310))
            ActionSearchWindow.shared.setPreview()
            render(ActionSearchView(model: ActionSearchWindow.shared), to: directory.appendingPathComponent("action-search.png"), size: NSSize(width: 580, height: 430))
            UserDefaults.standard.set(3, forKey: "timers.count")
            UserDefaults.standard.set(false, forKey: "timers.pageFocus")
            for (index, timer) in AppServices.shared.allTimers.enumerated() { timer.setPreview(remaining: Double(600 + index * 200), total: 1500) }
            render(TimersAppView(service: AppServices.shared.timerService).background(ThemeStore.shared.notch.surface).foregroundStyle(ThemeStore.shared.nookForeground).preferredColorScheme(.dark), to: directory.appendingPathComponent("timers-page.png"), size: NSSize(width: 620, height: 236))
            UserDefaults.standard.set(true, forKey: "timers.pageFocus")
            render(TimersAppView(service: AppServices.shared.timerService).background(ThemeStore.shared.notch.surface).foregroundStyle(ThemeStore.shared.nookForeground).preferredColorScheme(.dark), to: directory.appendingPathComponent("focus-page.png"), size: NSSize(width: 620, height: 236))
            captureMusicLayout(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "converter",
           let input = ProcessInfo.processInfo.environment["MACSPACES_CONVERTER_INPUT"] {
            // Every action on every sample (copies land beside the samples), then the wheel itself.
            let files = ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: input), includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            Task { @MainActor in
                var failures = 0
                for file in files {
                    for tools in [false, true] {
                        for action in FileConverter.actions(for: [file], tools: tools) {
                            do {
                                let outputs = try await FileConverter.run(action, on: [file]) { _ in }
                                let sizes = outputs.map { url -> String in
                                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                                    return "\(url.lastPathComponent) (\(size) B)"
                                }
                                print("OK   \(file.lastPathComponent) → \(action.title): \(sizes.joined(separator: ", "))")
                            } catch {
                                failures += 1
                                print("FAIL \(file.lastPathComponent) → \(action.title): \(error.localizedDescription)")
                            }
                        }
                    }
                }
                let sample = files.first { $0.pathExtension == "png" }.map { [$0] } ?? []
                for (name, tools, hovered) in [("formats", false, 1), ("tools", true, 0)] {
                    ConverterWheel.shared.preview(sample, tools: tools, hovered: hovered)
                    render(ConverterWheelView(wheel: ConverterWheel.shared).environment(\.colorScheme, .dark).padding(20)
                            .background(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)),
                           to: directory.appendingPathComponent("converter-wheel-\(name).png"), size: NSSize(width: 360, height: 360))
                }
                print("Converter checks: \(failures) failures")
                NSApp.terminate(nil)
            }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "basket" {
            // A file basket, empty and with synthetic files, over a backdrop to show the frosting.
            let files = directory.appendingPathComponent("Basket files", isDirectory: true)
            try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
            let names = ["Trip itinerary.md", "Budget.csv", "Poster draft.txt"]
            for name in names { try? "Sample\n".write(to: files.appendingPathComponent(name), atomically: true, encoding: .utf8) }
            for (label, filled) in [("empty", false), ("files", true)] {
                let store = ShelfStore(basketID: UUID())
                if filled { store.setPreviewItems(names.map { files.appendingPathComponent($0) }, selectedIndex: 0) }
                render(BasketPanelView(manager: BasketWindowController.shared, store: store, basket: FileBasket(name: "Weekend trip"))
                        .frame(width: 380, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(30)
                        .background(LinearGradient(colors: [.orange, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)),
                       to: directory.appendingPathComponent("basket-\(label).png"), size: NSSize(width: 440, height: 310))
                render(BasketBubble(manager: BasketWindowController.shared, store: store, basket: FileBasket(name: "Weekend trip"), open: {})
                        .frame(width: 64, height: 64).padding(28)
                        .background(LinearGradient(colors: [.orange, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)),
                       to: directory.appendingPathComponent("basket-bubble-\(label).png"), size: NSSize(width: 120, height: 120))
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "release-255" {
            let surface = ThemeStore.shared.notch.surface
            // Timers: the main timer plus two named ones (synthetic, never the user's).
            UserDefaults.standard.set(3, forKey: "timers.count")
            render(TimersAppView(service: TimerService(previewRemaining: 0, total: 0)).frame(width: 620, height: 196)
                    .background(surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("timers-page.png"), size: NSSize(width: 620, height: 196))
            // Teleprompter page and the prompter itself mid-script.
            render(PrompterPage(prompter: .shared).frame(width: 620, height: 340).background(surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("prompter-page.png"), size: NSSize(width: 620, height: 340))
            ScriptPrompter.shared.previewPlayback(at: 14)
            render(PrompterView(prompter: .shared), to: directory.appendingPathComponent("prompter-panel.png"), size: PrompterPanel.size)
            // A message banner.
            NotchBanners.shared.post(.init(source: .message(handle: "+15550100"), title: "Sam Rivera", detail: "Running 10 minutes late, save me a seat?"))
            render(NotchBannerView(banners: .shared), to: directory.appendingPathComponent("banner-message.png"), size: NotchBanners.size)
            render(ActivitiesSettingsPane().frame(width: 760, height: 1100),
                   to: directory.appendingPathComponent("settings-activities-255.png"), size: NSSize(width: 760, height: 1100))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "stickers" {
            // A filmstrip per sticker: the moments that matter, left to right.
            let times = [0.05, 0.2, 0.45, 0.7, 0.95, 1.3, 2.2]
            for sticker in LyricSticker.allCases {
                render(HStack(spacing: 0) {
                    ForEach(times, id: \.self) { time in
                        StickerPreview(sticker: sticker, accent: ThemeStore.shared.notch.accent, time: time).frame(width: 100, height: 100)
                    }
                }
                .background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                       to: directory.appendingPathComponent("sticker-\(sticker.rawValue).png"), size: NSSize(width: 700, height: 100))
            }
            render(HStack(spacing: 0) {
                ForEach([0.6, 0.9, 1.1, 1.5, 2.4], id: \.self) { time in
                    StickerPreview(sticker: .brokenHeart, accent: ThemeStore.shared.notch.accent, time: time).scaleEffect(2.5).frame(width: 240, height: 240)
                }
            }
            .background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("broken-heart-large.png"), size: NSSize(width: 1200, height: 240))
            render(HStack(spacing: 0) {
                ForEach([0.6, 1.0, 1.5, 2.0, 2.6], id: \.self) { time in
                    StickerPreview(sticker: .home, accent: ThemeStore.shared.notch.accent, time: time).scaleEffect(2.5).frame(width: 240, height: 240)
                }
            }
            .background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("home-large.png"), size: NSSize(width: 1200, height: 240))
            render(HStack(spacing: 0) {
                ForEach([0.6, 1.0, 1.5, 2.0, 2.6], id: \.self) { time in
                    StickerPreview(sticker: .world, accent: ThemeStore.shared.notch.accent, time: time).scaleEffect(2.5).frame(width: 240, height: 240)
                }
            }
            .background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("world-large.png"), size: NSSize(width: 1200, height: 240))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "secure-storage" {
            // The real device key (Secure Enclave when present), in the isolated fixtures folder.
            let sample = Data("A pinned snippet".utf8)
            let sealed = try! SecureStorage.seal(sample)
            let opened = try! SecureStorage.open(sealed)
            precondition(opened == sample && sealed.range(of: sample) == nil)
            let again = try! SecureStorage.open(sealed)   // cached key, same result
            precondition(again == sample)
            print("Secure storage checks passed: Secure Enclave \(SecureEnclave.isAvailable ? "used" : "unavailable, keychain key used"), round trip, nothing readable")
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "messages-inbox" {
            // Synthetic conversations only; the real Messages database is never read here.
            let now = Date()
            let chats: [MessageInboxReader.Chat] = [
                .init(id: "iMessage;-;+15550100", groupName: "", handle: "Sam Rivera", lastText: "Running 10 minutes late, save me a seat?", lastFromMe: false, lastDate: now.addingTimeInterval(-120)),
                .init(id: "iMessage;+;chat1", groupName: "Climbing crew", handle: "", lastText: "Saturday at 9?", lastFromMe: true, lastDate: now.addingTimeInterval(-3600)),
                .init(id: "iMessage;-;+15550101", groupName: "", handle: "Jo Park", lastText: "Sent the photos", lastFromMe: false, lastDate: now.addingTimeInterval(-90_000)),
            ]
            let thread: [MessageInboxReader.Line] = [
                .init(id: 1, fromMe: false, text: "Are we still on for dinner?", date: now.addingTimeInterval(-900), sender: "Sam Rivera"),
                .init(id: 2, fromMe: true, text: "Yes! 7:30 at the usual place", date: now.addingTimeInterval(-800), sender: "", reactions: ["❤️"]),
                .init(id: 3, fromMe: false, text: "Running 10 minutes late, save me a seat?", date: now.addingTimeInterval(-120), sender: "Sam Rivera",
                      reactions: ["👍", "😂"]),
                .init(id: 4, fromMe: true, text: "Here's the menu", date: now.addingTimeInterval(-60), sender: "",
                      attachments: [.init(path: "/nonexistent/menu.pdf", mimeType: "application/pdf", name: "menu.pdf")]),
            ]
            let service = AppServices.shared.messages
            service.setInboxPreview(chats, thread: thread)
            render(MessagesPage(service: service).frame(width: 620, height: 300).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("messages-page.png"), size: NSSize(width: 620, height: 300))
            // Notifications open their page when it's in the dock, and show a card otherwise.
            precondition(NotchBanners.page(for: .message(handle: "+1", chatID: "c"), dock: [.music, .messages]) == .messages)
            precondition(NotchBanners.page(for: .agent(sessionID: "s", appBundleID: ""), dock: [.terminal]) == .terminal)
            precondition(NotchBanners.page(for: .message(handle: "+1", chatID: "c"), dock: [.music]) == nil)
            precondition(NotchBanners.page(for: .app(bundleID: "com.example"), dock: NotchTab.allCases) == nil)
            NotchBanners.shared.post(.init(source: .message(handle: "+15550100", chatID: "iMessage;-;+15550100"), title: "Sam Rivera", detail: "Running 10 minutes late, save me a seat?"))
            NotchBanners.shared.beginReply()
            NotchBanners.shared.replyText = "On my way!"
            let replyFit = NotchBanners.shared.fittedSize()
            render(NotchBannerView(banners: .shared).frame(width: replyFit.width, height: replyFit.height),
                   to: directory.appendingPathComponent("banner-reply.png"), size: replyFit)
            NotchBanners.shared.dismiss()
            NotchBanners.shared.post(.init(source: .agent(sessionID: "a", appBundleID: "com.apple.Terminal"), title: "Claude · Lighthouse",
                                           detail: "Claude needs your permission to use Bash", persistent: true))
            let agentFit = NotchBanners.shared.fittedSize()
            precondition(agentFit.height < NotchBanners.size.height, "Cards fit their content (got \(agentFit.height))")
            render(NotchBannerView(banners: .shared).frame(width: agentFit.width, height: agentFit.height),
                   to: directory.appendingPathComponent("banner-agent.png"), size: agentFit)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "clock" {
            WidgetOptions.shared.clockPlaces = WidgetOptions.defaultWorldCities
            for (name, width, style) in [("dot-medium", 320.0, WidgetOptions.ClockStyle.dot), ("dot-large", 460.0, .dot), ("regular-large", 300.0, .regular)] {
                WidgetOptions.shared.clockStyle = style
                render(NookClockWidget(compact: false).frame(width: width, height: 170)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(14).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                       to: directory.appendingPathComponent("clock-\(name).png"), size: NSSize(width: width + 28, height: 198))
            }
            WidgetOptions.shared.clockStyle = .dot
            render(NookClockWidget(compact: true).frame(width: 116, height: 70).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("clock-dot-small.png"), size: NSSize(width: 116, height: 70))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "dock-settings" {
            let suite = "dev.opensource.MacSpaces.QA.dock." + UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = NookSettings(defaults: defaults)
            render(ScrollView { DockAppsCard(settings: settings).padding(20) }.frame(width: 640, height: 760)
                    .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("dock-settings.png"), size: NSSize(width: 640, height: 760))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "timers" {
            UserDefaults.standard.set(3, forKey: "timers.count")
            let surface = ThemeStore.shared.notch.surface
            render(TimersAppView(service: TimerService(previewRemaining: 0, total: 0)).frame(width: 620, height: 196)
                    .background(surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("timers-idle.png"), size: NSSize(width: 620, height: 196))
            render(HStack(spacing: 12) {
                ForEach(Array([577.0, 878, 1479].enumerated()), id: \.offset) { slot, left in
                    NookTimerWidget(service: TimerService(previewRemaining: left, total: 1500, slot: slot), compact: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12).frame(width: 620, height: 196).background(surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("timers-running.png"), size: NSSize(width: 620, height: 196))
            // The closed notch's times, each in its timer's colour.
            let running = [583.0, 1483, 1485].enumerated().map { TimerService(previewRemaining: $1, total: 1500, slot: $0) }
            render(HStack(spacing: 6) {
                Image(systemName: "timer").font(.system(size: 11, weight: .semibold)).foregroundStyle(running[0].tint)
                ForEach(running, id: \.slot) { Text($0.remainingText).foregroundStyle($0.tint) }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
            .frame(width: 200, height: 32).background(Color.black),
                   to: directory.appendingPathComponent("timers-notch.png"), size: NSSize(width: 200, height: 32))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "lyrics-258" {
            for style in [LyricStyle.stickers, .karaoke, .typewriter] {
                for (index, line) in ["Don't go breaking my heart tonight", "We drove the long road under the stars", "Follow the map back home", "Look how far you can see through", "We climb together through mountains", "Kids keep daydreaming beneath the summer sun"].enumerated() {
                    render(StyledLyricView(style: style, current: line, upcoming: "The next line waits here", accent: ThemeStore.shared.notch.accent,
                                           ink: ThemeStore.shared.nookForeground, animated: false, sequence: index, progress: 0.45)
                            .padding(16).frame(width: 420, height: 170).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                           to: directory.appendingPathComponent("lyric-\(style.rawValue)-\(index).png"), size: NSSize(width: 420, height: 170))
                }
            }
            render(SettingsView().frame(width: 980, height: 680), to: directory.appendingPathComponent("settings-window.png"), size: NSSize(width: 980, height: 680))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "activities" {
            render(ActivitiesSettingsPane().frame(width: 720, height: 900), to: directory.appendingPathComponent("activities-settings.png"), size: NSSize(width: 720, height: 900))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "coding" {
            CodingStats.shared.preview()
            AgentActivityMonitor.shared.preview()
            // The closed notch's agent lanes in each state.
            render(VStack(spacing: 10) {
                ForEach(AgentActivityMonitor.shared.sessions) { session in
                    HStack(spacing: 0) {
                        AgentActivityGlyph(session: session, accent: .gray).frame(width: 58)
                        Color.black.frame(width: 185, height: 32)
                        AgentActivityPulse(state: session.state, agent: session.agent).frame(width: 58)
                    }
                    .frame(height: 32).background(Color(white: 0.08), in: Capsule())
                }
            }
            .padding(12).background(Color(white: 0.3)),
                   to: directory.appendingPathComponent("agent-notch.png"), size: NSSize(width: 325, height: 150))
            // The real closed notch with an agent working: lanes fit their content.
            let notchSuite = "MacSpaces.NotchQA." + UUID().uuidString
            let notchDefaults = UserDefaults(suiteName: notchSuite)!
            defer { notchDefaults.removePersistentDomain(forName: notchSuite) }
            let notchPlayer = NowPlayingController()
            let closed = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
                settings: NookSettings(defaults: notchDefaults), shelf: ShelfStore(basketID: UUID()), nowPlaying: notchPlayer,
                powerMonitor: AppServices.shared.powerMonitor, timerService: AppServices.shared.timerService,
                bluetoothMonitor: AppServices.shared.bluetooth, systemActivityMonitor: AppServices.shared.systemActivity,
                teleprompter: TeleprompterService(nowPlaying: notchPlayer))
            render(NotchContainerView(viewModel: closed).frame(width: 420, height: 60, alignment: .top).background(Color(white: 0.55)),
                   to: directory.appendingPathComponent("agent-notch-closed.png"), size: NSSize(width: 420, height: 60))
            precondition(closed.measuredLaneContent > 0 && closed.collapsedSize.width == closed.geometry.width + closed.collapsedLeftLaneWidth + closed.collapsedRightLaneWidth, "Each agent lane fits independently")
            for tab in CodingPanel.Tab.allCases where tab != .shell {
                render(CodingPanel(tab: tab).frame(width: 760, height: 330).padding(20).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                       to: directory.appendingPathComponent("coding-\(tab.rawValue).png"), size: NSSize(width: 800, height: 370))
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "site-converter" {
            // Frames for the website's File Converter clip: formats, then tools landing on Under 1 MB.
            let samples = directory.appendingPathComponent("site-samples", isDirectory: true)
            try? FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
            let photo = samples.appendingPathComponent("Golden hour.png")
            let size = NSSize(width: 800, height: 520)
            let picture = NSImage(size: size)
            picture.lockFocus()
            NSGradient(colors: [NSColor(red: 0.98, green: 0.62, blue: 0.35, alpha: 1), NSColor(red: 0.55, green: 0.32, blue: 0.62, alpha: 1)])?
                .draw(in: NSRect(origin: .zero, size: size), angle: -70)
            NSColor(white: 1, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 520, y: 300, width: 120, height: 120)).fill()
            NSColor(red: 0.2, green: 0.12, blue: 0.25, alpha: 0.9).setFill()
            let hills = NSBezierPath(); hills.move(to: .zero)
            hills.curve(to: NSPoint(x: 800, y: 120), controlPoint1: NSPoint(x: 260, y: 260), controlPoint2: NSPoint(x: 520, y: 40))
            hills.line(to: NSPoint(x: 800, y: 0)); hills.close(); hills.fill()
            picture.unlockFocus()
            if let tiff = picture.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) { try? rep.representation(using: .png, properties: [:])?.write(to: photo) }
            let wheel = ConverterWheel.shared
            var frame = 0
            func shot(tools: Bool, hovered: Int?) {
                wheel.preview([photo], tools: tools, hovered: hovered)
                // MACSPACES_CONVERTER_BG=white or black renders on a flat colour (a pair gives transparency).
                let flat = ProcessInfo.processInfo.environment["MACSPACES_CONVERTER_BG"]
                render(ZStack {
                    if let flat {
                        (flat == "white" ? Color.white : Color.black)
                    } else {
                        LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.24), Color(red: 0.36, green: 0.27, blue: 0.42)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    ConverterWheelView(wheel: wheel).environment(\.colorScheme, .dark).scaleEffect(1.75)
                }
                .frame(width: 1200, height: 702),
                       to: directory.appendingPathComponent(String(format: "site-converter-%03d.png", frame)), size: NSSize(width: 1200, height: 702))
                frame += 1
            }
            shot(tools: false, hovered: nil)
            for index in 0..<min(5, max(1, FileConverter.actions(for: [photo], tools: false).count)) { shot(tools: false, hovered: index) }
            let tools = FileConverter.actions(for: [photo], tools: true)
            shot(tools: true, hovered: nil)
            if let target = tools.firstIndex(where: { $0.id == "tool.under1mb" }) { shot(tools: true, hovered: target) }
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "wheel" {
            // The converter wheel with one, two and many choices.
            let samples = directory.appendingPathComponent("wheel-samples", isDirectory: true)
            try? FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
            for name in ["archive.zip", "notes.txt", "photo.png"] { try? Data("x".utf8).write(to: samples.appendingPathComponent(name)) }
            for (name, tools) in [("archive.zip", false), ("archive.zip", true), ("notes.txt", true), ("photo.png", false)] {
                let wheel = ConverterWheel.shared
                wheel.preview([samples.appendingPathComponent(name)], tools: tools, hovered: 0)
                render(ConverterWheelView(wheel: wheel).frame(width: 320, height: 320)
                        .background(LinearGradient(colors: [.orange, .purple], startPoint: .top, endPoint: .bottom)),
                       to: directory.appendingPathComponent("wheel-\(name)-\(tools ? "tools" : "formats")-\(wheel.actions.count).png"),
                       size: NSSize(width: 320, height: 320))
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "tools-254" {
            // 2.54's widgets and settings, with synthetic input only.
            let surface = ThemeStore.shared.notch.surface
            for (name, input) in [("math", "15% of 80 + 2^5"), ("units", "5 km in mi")] {
                render(CalculatorWidget(initialInput: input).frame(width: 260, height: 130).background(surface).preferredColorScheme(.dark),
                       to: directory.appendingPathComponent("calculator-\(name).png"), size: NSSize(width: 260, height: 130))
            }
            render(DevServersWidget().frame(width: 300, height: 150).background(surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("dev-servers.png"), size: NSSize(width: 300, height: 150))
            render(ActivitiesSettingsPane().frame(width: 760, height: 760),
                   to: directory.appendingPathComponent("settings-activities.png"), size: NSSize(width: 760, height: 760))
            render(GeneralSettingsPane().frame(width: 760, height: 1700),
                   to: directory.appendingPathComponent("settings-general.png"), size: NSSize(width: 760, height: 1700))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "clipboard-popup-live" {
            // The real panel: it must take the keyboard without activating MacSpaces,
            // type into search, move with the arrows and close with Escape.
            AppServices.shared.clipboard.setPreviewEntries(["alpha", "north gate", "beta", "gamma"])
            let popup = ClipboardPopup.shared
            popup.show()
            func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) {
                guard let window = NSApp.keyWindow, let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { return }
                NSApp.sendEvent(event)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let window = NSApp.keyWindow
                precondition(popup.isShown && window != nil, "The popup takes the keyboard")
                precondition(window?.firstResponder is NSTextView, "Search has focus")
                for character in "nor" { key(0, String(character)) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    precondition(popup.model.query == "nor", "Typing searches (got \(popup.model.query))")
                    precondition(popup.model.items.map(\.text) == ["north gate"])
                    key(UInt16(kVK_ANSI_U), "u", .control)
                    precondition(popup.model.query.isEmpty && popup.model.items.count == 4)
                    key(UInt16(kVK_DownArrow), "\u{F701}"); key(UInt16(kVK_DownArrow), "\u{F701}")
                    precondition(popup.model.cursor == 2, "Arrows move the selection")
                    key(UInt16(kVK_UpArrow), "\u{F700}", .shift)
                    precondition(popup.model.selection.count == 2, "Shift-arrows choose several")
                    key(UInt16(kVK_Escape), "\u{1B}")
                    precondition(!popup.isShown, "Escape closes it")
                    print("Clipboard popup checks passed: keyboard focus, search, clear search, arrows, multi-select and Escape")
                    NSApp.terminate(nil)
                }
            }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "site-themes" {
            // Every theme drawer open, as in Settings → Appearance, for the website's Themes tab.
            ThemeStore.shared.selectFamily(.everforest)
            ThemeStore.shared.appearanceMode = .dark
            NookThemePicker.startsFullyOpen = true
            ThemeStore.shared.showsPatterns = true
            ThemeStore.shared.animatesEffects = true
            let picker = NookThemePicker().padding(24).frame(width: 760)
                .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark)
            let height = NSHostingView(rootView: picker).fittingSize.height
            render(picker.frame(height: height), to: directory.appendingPathComponent("themes-all.png"), size: NSSize(width: 760, height: height))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "site-green" {
            // Website stills in Everforest: the clipboard popup, the Messages page and the
            // coding tabs, all with synthetic data (no real clips, messages or logs).
            ThemeStore.shared.selectFamily(.everforest)
            let surface = ThemeStore.shared.notch.surface
            let monitor = ClipboardMonitor()
            monitor.setPreviewEntries(["Quarterly summary, second draft\nwith notes from Thursday", "https://example.com/launch-notes",
                                       "#3E6A34", "brew upgrade", "Meet at the north entrance", "Invoice 1042", "#F4C095",
                                       "let total = items.reduce(0, +)", "Weekend plan", "Flight AB 123, seat 14C", "Ten"])
            if let first = monitor.entries.first { _ = monitor.toggleFavorite(first) }
            let model = ClipboardPopup.shared.model
            model.open(monitor: monitor)
            model.setCursor(1)
            render(ClipboardPopupView(model: model).frame(width: 660, height: 440).background(surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("clipboard-popup-green.png"), size: NSSize(width: 660, height: 440))
            let now = Date()
            AppServices.shared.messages.setInboxPreview([
                .init(id: "iMessage;-;+15550100", groupName: "", handle: "Sam Rivera", lastText: "Running 10 minutes late, save me a seat?", lastFromMe: false, lastDate: now.addingTimeInterval(-120)),
                .init(id: "iMessage;+;chat1", groupName: "Climbing crew", handle: "", lastText: "Saturday at 9?", lastFromMe: true, lastDate: now.addingTimeInterval(-3600)),
                .init(id: "iMessage;-;+15550101", groupName: "", handle: "Jo Park", lastText: "Sent the photos", lastFromMe: false, lastDate: now.addingTimeInterval(-90_000)),
                .init(id: "iMessage;-;+15550102", groupName: "", handle: "Alex Kim", lastText: "Loved the playlist", lastFromMe: false, lastDate: now.addingTimeInterval(-180_000)),
            ], thread: [
                .init(id: 1, fromMe: false, text: "Are we still on for dinner?", date: now.addingTimeInterval(-900), sender: "Sam Rivera"),
                .init(id: 2, fromMe: true, text: "Yes! 7:30 at the usual place", date: now.addingTimeInterval(-800), sender: "", reactions: ["❤️"]),
                .init(id: 3, fromMe: false, text: "Running 10 minutes late, save me a seat?", date: now.addingTimeInterval(-120), sender: "Sam Rivera", reactions: ["👍"]),
                .init(id: 4, fromMe: true, text: "No rush, I'll order the dumplings", date: now.addingTimeInterval(-60), sender: ""),
            ])
            render(MessagesPage(service: AppServices.shared.messages).frame(width: 720, height: 320).background(surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("messages-green.png"), size: NSSize(width: 720, height: 320))
            // The Tray page with a few synthetic project files.
            let trayFolder = directory.appendingPathComponent("Tray files", isDirectory: true)
            try? FileManager.default.createDirectory(at: trayFolder, withIntermediateDirectories: true)
            var trayFiles: [URL] = []
            let plan = "# Launch plan\n\n" + (1...14).map { "- Step \($0): notarize, tag, update the tap and check the site" }.joined(separator: "\n")
            let budget = "Item,Cost,Owner\n" + ["Venue", "Prints", "Catering", "Lighting", "Sound", "Signage", "Travel", "Posters", "Coffee", "Flowers", "Tickets", "Badges"]
                .enumerated().map { "\($1),\(120 * ($0 + 1)),Sam" }.joined(separator: "\n")
            let notes = (1...16).map { "Question \($0): what would make the first week easier for someone new to the team?" }.joined(separator: "\n\n")
            for (name, text) in [("Launch plan.md", plan), ("Budget.csv", budget), ("Interview notes.txt", notes)] {
                let url = trayFolder.appendingPathComponent(name)
                try? text.write(to: url, atomically: true, encoding: .utf8)
                trayFiles.append(url)
            }
            let photo = trayFolder.appendingPathComponent("Cover draft.png")
            let picture = NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
                NSGradient(colors: [NSColor(srgbRed: 0.65, green: 0.75, blue: 0.5, alpha: 1), NSColor(srgbRed: 0.2, green: 0.33, blue: 0.24, alpha: 1)])?.draw(in: rect, angle: -60)
                NSColor(white: 1, alpha: 0.85).setFill()
                NSBezierPath(ovalIn: NSRect(x: 200, y: 200, width: 200, height: 200)).fill()
                return true
            }
            if let tiff = picture.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: photo); trayFiles.insert(photo, at: 0)
            }
            let tray = ShelfStore(basketID: UUID())
            tray.setPreviewItems(trayFiles, selectedIndex: 0)
            // Thumbnails load asynchronously: render once to start them, then capture.
            for _ in 0..<2 {
                render(TrayPageView(tray: tray, isDropTargeted: .constant(false)).frame(width: 700, height: 210).padding(10).background(surface).preferredColorScheme(.dark),
                       to: directory.appendingPathComponent("tray-green.png"), size: NSSize(width: 720, height: 230))
                RunLoop.main.run(until: Date().addingTimeInterval(2))
            }
            CodingStats.shared.preview()
            AgentActivityMonitor.shared.preview()
            for tab in [CodingPanel.Tab.agents, .usage] {
                render(CodingPanel(tab: tab).frame(width: 760, height: 330).padding(20).background(surface).preferredColorScheme(.dark),
                       to: directory.appendingPathComponent("coding-green-\(tab.rawValue).png"), size: NSSize(width: 800, height: 370))
            }
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "clipboard-popup" {
            // The history popup and Settings → Clipboard, with synthetic clips only.
            let monitor = ClipboardMonitor()
            monitor.setPreviewEntries(["Quarterly summary, second draft\nwith notes from Thursday", "https://example.com/launch-notes",
                                       "#3E6A34", "brew upgrade", "Meet at the north entrance", "Invoice 1042", "#F4C095",
                                       "let total = items.reduce(0, +)", "Weekend plan", "Flight AB 123, seat 14C", "Ten"])
            if let first = monitor.entries.first { _ = monitor.toggleFavorite(first) }
            let model = ClipboardPopup.shared.model
            model.open(monitor: monitor)
            model.setCursor(1)
            render(ClipboardPopupView(model: model).frame(width: 660, height: 440).padding(30)
                    .background(LinearGradient(colors: [.orange, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)),
                   to: directory.appendingPathComponent("clipboard-popup.png"), size: NSSize(width: 720, height: 500))
            model.query = "nort"
            render(ClipboardPopupView(model: model).frame(width: 660, height: 440).padding(30)
                    .background(LinearGradient(colors: [.orange, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)),
                   to: directory.appendingPathComponent("clipboard-popup-search.png"), size: NSSize(width: 720, height: 500))
            render(ClipboardSettingsPane().frame(width: 760, height: 1500),
                   to: directory.appendingPathComponent("clipboard-settings.png"), size: NSSize(width: 760, height: 1500))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "clipboard-queue" {
            // The paste queue on the Clipboard page and widget, with synthetic clips only.
            let monitor = ClipboardMonitor()
            monitor.setPreviewEntries(["Quarterly summary, second draft", "https://example.com/launch-notes", "brew upgrade",
                                       "Meet at the north entrance", "Invoice 1042"])
            for (label, access) in [("ready", false), ("access", true)] {
                monitor.setPreviewQueue(["Quarterly summary, second draft", "https://example.com/launch-notes", "Meet at the north entrance"],
                                        needsAccess: access)
                render(ClipboardAppView(monitor: monitor).frame(width: 740, height: 300)
                        .background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                       to: directory.appendingPathComponent("clipboard-queue-\(label).png"), size: NSSize(width: 740, height: 300))
                render(ClipboardWidget(monitor: monitor).frame(width: 260, height: 150)
                        .background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                       to: directory.appendingPathComponent("clipboard-widget-\(label).png"), size: NSSize(width: 260, height: 150))
            }
            // The Nook's Tray page switching between the Tray and two baskets.
            let files = directory.appendingPathComponent("Basket files", isDirectory: true)
            try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
            let names = ["Trip itinerary.md", "Budget.csv", "Poster draft.txt"]
            for name in names { try? "Sample\n".write(to: files.appendingPathComponent(name), atomically: true, encoding: .utf8) }
            BasketWindowController.shared.setPreviewBaskets([("Weekend trip", names.map { files.appendingPathComponent($0) }),
                                                            ("Receipts", [])])
            let tray = ShelfStore(basketID: UUID())
            tray.setPreviewItems([files.appendingPathComponent(names[0])], selectedIndex: nil)
            render(TrayPageView(tray: tray, isDropTargeted: .constant(false)).padding(20).frame(width: 740, height: 260)
                    .background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("tray-page-baskets.png"), size: NSSize(width: 740, height: 260))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "lyric-styles" {
            captureLyricStyles(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "music-layout" {
            captureMusicLayout(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        let clipboard = ClipboardMonitor()
        clipboard.setPreviewEntries(["Design review at 10:30", "A small space for a clear head."])
        _ = clipboard.toggleFavorite(clipboard.entries[0])
        let stats = SystemStatsService(); stats.setPreview()
        let awake = KeepAwakeService()
        for preset in [ThemePreset.midnight, .forest, .frosted] {
            ThemeStore.shared.setPreset(preset, for: .notch)
            let view = HStack(spacing: 14) {
                tile("Clipboard") { ClipboardWidget(monitor: clipboard) }
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
        lyrics.setPreview(current: "A synthetic lyric line", upcoming: "The next line stays readable", source: .lyrics)
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
            ("sound", [.mirror, .clock, .pomodoro])
        ]
        // Explicit sizes: stacked smalls of every kind next to large tiles.
        let sizedProfiles: [(String, [(NookWidgetKind, NookWidgetSize)])] = [
            ("sizes-a", [(.media, .small), (.calendar, .small), (.weather, .large), (.clock, .small), (.timer, .small)]),
            ("sizes-b", [(.calendar, .large), (.clipboard, .small), (.notes, .small), (.systemStats, .small), (.keepAwake, .small)]),
            ("sizes-c", [(.todos, .medium), (.pomodoro, .small), (.quickActions, .large), (.battery, .small), (.systemStats, .medium)]),
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
            // One profile shows a selected widget (click to select, Delete to remove).
            if name == "everyday" { model.selectedWidget = .weather }
            render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("home-" + name + ".png"),
                   size: NSSize(width: model.expandedSize.width + 52, height: model.expandedSize.height + 28))
        }
        // The Terminal widget after a quick command (QA bundle only; harmless output).
        dockSettings.widgets = [.terminal, .clock, .timer]
        dockSettings.setSize(.large, for: .terminal)
        AppServices.shared.quickShell.start()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        AppServices.shared.quickShell.run("printf '\\033[32m==>\\033[0m Installing tree\\n\\033[32m✓\\033[0m tree 2.2.1 installed\\n'")
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        let shellModel = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
            settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
            timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
            systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
        shellModel.state = .expanded
        render(NotchContainerView(viewModel: shellModel), to: directory.appendingPathComponent("home-terminal.png"),
               size: NSSize(width: shellModel.expandedSize.width + 52, height: shellModel.expandedSize.height + 28))
        dockSettings.setSize(.medium, for: .terminal)
        dockSettings.widgets = [.terminal, .weather, .systemStats, .clock, .timer]
        render(NotchContainerView(viewModel: shellModel), to: directory.appendingPathComponent("home-terminal-medium.png"),
               size: NSSize(width: shellModel.expandedSize.width + 52, height: shellModel.expandedSize.height + 28))
        // The Terminal page shares the widget's shell.
        let savedDock = dockSettings.dockApps
        dockSettings.dockApps = [.music, .calendar, .terminal, .weather, .tray]
        let pageModel = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
            settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
            timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
            systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
        pageModel.state = .expanded
        pageModel.selectedTab = .terminal
        render(NotchContainerView(viewModel: pageModel), to: directory.appendingPathComponent("page-terminal.png"),
               size: NSSize(width: pageModel.expandedSize.width + 52, height: pageModel.expandedSize.height + 28))
        // The Shortcuts page (your own shortcut names; QA output only).
        let shortcutsModel = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
            settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
            timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
            systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
        shortcutsModel.state = .expanded
        shortcutsModel.selectedTab = .shortcuts
        AppServices.shared.shortcuts.startIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        render(NotchContainerView(viewModel: shortcutsModel), to: directory.appendingPathComponent("page-shortcuts.png"),
               size: NSSize(width: shortcutsModel.expandedSize.width + 52, height: shortcutsModel.expandedSize.height + 28))
        dockSettings.dockApps = savedDock
        AppServices.shared.quickShell.stop()
        // Two Home versions: the dock gains a third capsule, one button per Home.
        let firstHome = dockSettings.activeProfile
        dockSettings.addProfile(named: "Profile", copyingCurrent: true)
        let secondHome = dockSettings.activeProfile
        let versionsModel = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
            settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
            timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
            systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
        versionsModel.state = .expanded
        render(NotchContainerView(viewModel: versionsModel), to: directory.appendingPathComponent("home-versions.png"),
               size: NSSize(width: versionsModel.expandedSize.width + 52, height: versionsModel.expandedSize.height + 28))
        dockSettings.removeProfile(secondHome)
        dockSettings.activeProfileID = firstHome.id
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
        AppServices.shared.calendar.setAppPreview()
        dockSettings.dockApps = NotchTab.appPages
        for tab in [NotchTab.music, .calendar, .notes, .weather, .reminders, .timers, .clipboard, .system] {
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
    /// The Music page in every lyric style, in two themes, plus the Settings picker.
    private static func captureLyricStyles(to directory: URL) {
        let player = NowPlayingController()
        let lyrics = TeleprompterService(nowPlaying: player)
        var track = NowPlayingInfo()
        track.title = "Harbour Lights"; track.artist = "Sample Artist"; track.album = "Low Tide"
        track.sourceName = "Music"; track.capabilities = [.playPause, .previous, .next, .seek]
        track.duration = 236; track.elapsed = 81; track.isPlaying = true
        // Original, synthetic cover art.
        track.artwork = NSImage(size: NSSize(width: 360, height: 360), flipped: false) { rect in
            NSGradient(colors: [.init(srgbRed: 0.1, green: 0.16, blue: 0.3, alpha: 1),
                                .init(srgbRed: 0.85, green: 0.45, blue: 0.4, alpha: 1)])?.draw(in: rect, angle: 70)
            NSColor(srgbRed: 1, green: 0.86, blue: 0.62, alpha: 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 200, y: 190, width: 90, height: 90)).fill()
            return true
        }
        player.setPreviewInfo(track)
        let store = ThemeStore.shared
        let saved = (store.family, store.lyricStyle, store.animatesEffects)
        store.animatesEffects = false
        for family in [ThemeFamily.macspaces, .karma] {
            store.selectFamily(family); store.appearanceMode = .dark
            for style in LyricStyle.allCases {
                store.lyricStyle = style
                lyrics.setPreview(current: "We left the windows open", upcoming: "", source: .lyrics)
                render(MediaPlayerView(nowPlaying: player, style: .studio, largeArtwork: true, lyricsService: lyrics)
                    .frame(width: 572, height: 272)
                    .background(store.notch.surface)
                    .foregroundStyle(store.nookForeground)
                    .environment(\.colorScheme, .dark),
                    to: directory.appendingPathComponent("lyrics-\(family.rawValue)-\(style.rawValue).png"),
                    size: NSSize(width: 572, height: 272)) {
                        // The second line arrives while the page is showing, as in playback.
                        // Stickers needs a line that mentions something drawable.
                        lyrics.setPreview(current: style == .stickers ? "Don't go breaking my heart tonight" : "Hold the evening light a little longer",
                                          upcoming: "Till the harbour lamps come on", source: .lyrics)
                    }
            }
        }
        render(LyricStylePicker().padding(20).frame(width: 640).background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .dark),
               to: directory.appendingPathComponent("lyrics-settings.png"), size: NSSize(width: 640, height: 330))
        // Poster edge cases: a long headline with a long tail, a long lead-in, one word.
        store.selectFamily(.macspaces); store.appearanceMode = .dark; store.lyricStyle = .poster
        for (index, line) in ["I don't get starstruck easily anymore these days",
                              "And when we were young we would run through the evening",
                              "Starstruck"].enumerated() {
            lyrics.setPreview(current: line, upcoming: "", source: .lyrics)
            render(MediaPlayerView(nowPlaying: player, style: .studio, largeArtwork: true, lyricsService: lyrics)
                .frame(width: 572, height: 272)
                .background(store.notch.surface)
                .foregroundStyle(store.nookForeground)
                .environment(\.colorScheme, .dark),
                to: directory.appendingPathComponent("lyrics-poster-edge-\(index).png"), size: NSSize(width: 572, height: 272))
        }
        // Each Poster composition on the same lines.
        for (index, composition) in PosterLyric.Composition.allCases.enumerated() {
            let lines = ["I don't get starstruck easily anymore these days", "Need I go any further on",
                         "And when we were young we would run through the evening"]
            render(VStack(spacing: 10) {
                    ForEach(lines, id: \.self) { line in
                        PosterLyric(line: line, accent: store.notch.accent, ink: store.nookForeground,
                                    size: CGSize(width: 340, height: 130), composition: composition)
                            .frame(width: 340, height: 130)
                    }
                }
                .padding(16).background(store.notch.surface).environment(\.colorScheme, .dark),
                to: directory.appendingPathComponent("poster-composition-\(index).png"), size: NSSize(width: 372, height: 442))
        }
        // Every scene theme's effect at Nook size, grouped as in Settings.
        for collection in ThemeCollection.allCases where collection != .core && collection != .terminal {
            for family in collection.families {
                store.selectFamily(family); store.appearanceMode = .dark
                guard let motif = family.motif else { continue }
                render(ThemeMotifView(motif: motif, accent: store.notch.accent, ink: store.nookForeground, softensCenter: true)
                        .background(store.notch.surface),
                       to: directory.appendingPathComponent("scene-\(collection.rawValue)-\(family.rawValue).png"), size: NSSize(width: 640, height: 280))
            }
        }
        if let family = saved.0 { store.selectFamily(family) }
        store.lyricStyle = saved.1; store.animatesEffects = saved.2
        print("Lyric style captures passed: \(LyricStyle.allCases.count) styles in two themes and the Settings picker.")
    }

    private static func captureMusicLayout(to directory: URL) {
        let player = NowPlayingController()
        let lyrics = TeleprompterService(nowPlaying: player)
        var track = NowPlayingInfo()
        track.title = "Evening light"
        track.artist = "Sample Artist"
        track.album = "After the rain"
        track.sourceName = "Music"
        track.capabilities = [.playPause, .previous, .next, .seek]
        track.duration = 240
        track.elapsed = 75
        track.isPlaying = true
        // Original, synthetic cover art for native layout captures.
        track.artwork = NSImage(size: NSSize(width: 360, height: 360), flipped: false) { rect in
            NSGradient(colors: [.init(srgbRed: 0.12, green: 0.2, blue: 0.27, alpha: 1),
                                .init(srgbRed: 0.63, green: 0.49, blue: 0.39, alpha: 1)])?.draw(in: rect, angle: 55)
            NSColor(srgbRed: 0.94, green: 0.82, blue: 0.65, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 120, y: 120, width: 120, height: 120)).fill()
            return true
        }
        for preset in [ThemePreset.midnight, .gruvboxDark, .forest] {
            ThemeStore.shared.setPreset(preset, for: .notch)
            player.setPreviewInfo(track)
            lyrics.setPreview(current: "A little light across the water", upcoming: "And a quiet place to land", source: .lyrics)
            renderMusicLayout(player, lyrics: lyrics, name: "music-layout-" + preset.rawValue, directory: directory)
        }
        ThemeStore.shared.setPreset(.midnight, for: .notch)
        track.title = "A long track title that should wrap without moving the playback controls"
        player.setPreviewInfo(track)
        lyrics.setPreview(current: "A longer lyric that needs more than one line to remain comfortably readable",
                          upcoming: "The next line still fits below", source: .lyrics)
        renderMusicLayout(player, lyrics: lyrics, name: "music-layout-long", directory: directory)
        track.title = "Live stream"; track.duration = 0; track.capabilities.remove(.seek)
        player.setPreviewInfo(track)
        lyrics.setPreview(current: "", upcoming: "", source: .lyrics)
        renderMusicLayout(player, lyrics: lyrics, name: "music-layout-live", directory: directory)
        player.setPreviewInfo(NowPlayingInfo())
        renderMusicLayout(player, lyrics: lyrics, name: "music-layout-empty", directory: directory)
        print("Standalone Music layout captures passed: three themes, long metadata/lyrics, live stream and empty playback.")
    }

    private static func renderMusicLayout(_ player: NowPlayingController, lyrics: TeleprompterService,
                                          name: String, directory: URL) {
        render(MediaPlayerView(nowPlaying: player, style: .studio, largeArtwork: true, lyricsService: lyrics)
            .frame(width: 532, height: 272)
            .background(ThemeStore.shared.notch.surface)
            .foregroundStyle(ThemeStore.shared.nookForeground)
            .environment(\.colorScheme, .dark),
            to: directory.appendingPathComponent(name + ".png"), size: NSSize(width: 532, height: 272))
    }

    private static func renderMusic(_ player: NowPlayingController, name: String, directory: URL) {
        let view = MediaPlayerView(nowPlaying: player, style: .studio, largeArtwork: true)
            .frame(width: 532, height: 272)
            .background(ThemeStore.shared.notch.surface)
            .foregroundStyle(ThemeStore.shared.nookForeground)
            .environment(\.colorScheme, .dark)
        render(view, to: directory.appendingPathComponent(name + ".png"), size: NSSize(width: 532, height: 272))
    }
    private static func tile<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(12).frame(width: 240, height: 240)
            .background(ThemeStore.shared.notch.control, in: RoundedRectangle(cornerRadius: 16))
    }
    private static func render<V: View>(_ view: V, to url: URL, size: NSSize = NSSize(width: 1134, height: 276),
                                        whileShowing change: (() -> Void)? = nil) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; window.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        if let change {
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            change()
        }
        // Let entrance animations (the Nook's tile drop) settle before capture.
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
#endif
