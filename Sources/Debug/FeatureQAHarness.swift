#if DEBUG
import AppKit
import CryptoKit
import Carbon.HIToolbox
import SwiftUI
import SwiftTerm

@MainActor enum FeatureQAHarness {
    /// The agent bubble beside a closed notch: needing you (at rest and at full pulse),
    /// working, ticked after a finish, and two waiting (with a count), in
    /// two themes; and where clicking it lands, the Agents tab with that session outlined.
    static func captureAgentPopout(to directory: URL) {
        AgentActivityMonitor.shared.preview()
        let sessions = AgentActivityMonitor.shared.sessions
        let popout = AgentPopout.shared
        func strip(time: Double) -> some View {
            HStack(spacing: AgentPopoutLayout.gap) {
                // A closed notch with a music lane, then the bubble, as on screen.
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(Color.black)
                    .frame(width: 260, height: 32)
                AgentPopoutView(popout: popout, stillTime: time).frame(width: 32, height: 32)
            }
            .padding(.horizontal, 24).padding(.bottom, 14)
            .frame(width: 360, height: 46, alignment: .top)
            .background(LinearGradient(colors: [Color(white: 0.82), Color(white: 0.7)], startPoint: .top, endPoint: .bottom))
        }
        let waiting = sessions.filter { $0.id == "b" }, working = sessions.filter { $0.state == .working }
        // Mid-hop is 0.7 of a breath; mid-glance toward the camera is 2.5 s into a look.
        for family in [ThemeFamily.macspaces, .everforest] {
            ThemeStore.shared.selectFamily(family)
            popout.setPreview(waiting, mood: .needsYou)
            render(VStack(spacing: 0) { strip(time: 0); strip(time: 1.12) },
                   to: directory.appendingPathComponent("agent-popout-\(family.rawValue).png"), size: NSSize(width: 360, height: 92))
            popout.setPreview(working, mood: .working)
            render(VStack(spacing: 0) { strip(time: 0.5); strip(time: 2.5) },
                   to: directory.appendingPathComponent("agent-popout-working-\(family.rawValue).png"), size: NSSize(width: 360, height: 92))
            popout.setPreview([], mood: .cheering)
            render(strip(time: 0.5), to: directory.appendingPathComponent("agent-popout-done-\(family.rawValue).png"), size: NSSize(width: 360, height: 46))
        }
        ThemeStore.shared.selectFamily(.macspaces)
        // Large, to read the bubble: each state at 4x.
        for mood in [AgentFace.Mood.working, .needsYou, .cheering] {
            popout.setPreview(mood == .working ? [] : waiting, mood: mood)
            render(AgentPopoutView(popout: popout, stillPulse: 1).frame(width: 128, height: 128).padding(24).background(Color(white: 0.75)),
                   to: directory.appendingPathComponent("agent-bubble-\(mood).png"), size: NSSize(width: 176, height: 176))
        }
        popout.setPreview(waiting, mood: .needsYou)
        var second = sessions.first { $0.id == "a" }!
        second = AgentActivityMonitor.Session(id: "d", agent: "codex", state: .needsYou, folder: second.folder, updated: Date())
        popout.setPreview(waiting + [second], mood: .needsYou)
        render(strip(time: 0), to: directory.appendingPathComponent("agent-popout-two.png"), size: NSSize(width: 360, height: 46))
        precondition(popout.waiting.count == 2, "Both waiting sessions count")
        AgentActivityMonitor.shared.spotlight = "b"
        render(CodingPanel(tab: .agents).frame(width: 580, height: 270).padding(20).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
               to: directory.appendingPathComponent("agents-spotlight.png"), size: NSSize(width: 620, height: 310))
        render(ActivitiesSettingsPane().frame(width: 760, height: 820).preferredColorScheme(.dark),
               to: directory.appendingPathComponent("settings-activities.png"), size: NSSize(width: 760, height: 820))
        print("Agent pop-out captures written")
    }

    /// The Terminal page's rail and its Homebrew tab with synthetic packages (Homebrew is
    /// never run or read): outdated, everything current, a command running, one that needs
    /// a password, and Homebrew missing; the page on Shell and Agents in three themes.
    static func captureHomebrew(to directory: URL) {
        let store = HomebrewStore.shared
        func package(_ kind: HomebrewPackage.Kind, _ name: String, _ title: String? = nil, _ installed: String, _ latest: String? = nil,
                     pinned: Bool = false, autoUpdates: Bool = false) -> HomebrewPackage {
            HomebrewPackage(kind: kind, name: name, title: title ?? name, installed: installed, latest: latest ?? installed,
                            outdated: latest != nil, pinned: pinned, autoUpdates: autoUpdates)
        }
        let packages = [
            package(.formula, "node", nil, "24.9.0", "24.11.1"), package(.formula, "gh", nil, "2.81.0", "2.83.0"),
            package(.cask, "visual-studio-code", "Visual Studio Code", "1.105.0", "1.106.1", autoUpdates: true),
            package(.formula, "ffmpeg", nil, "8.0", "8.0.1", pinned: true), package(.formula, "git", nil, "2.51.2"),
            package(.formula, "python@3.14", nil, "3.14.0"), package(.formula, "ripgrep", nil, "15.1.0"),
            package(.cask, "iterm2", "iTerm2", "3.6.4"), package(.formula, "xcodegen", nil, "2.44.1"),
        ].sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let updated = Date().addingTimeInterval(-7200)
        let shell = QuickShell(defaults: UserDefaults(suiteName: "FeatureQA.homebrew")!)
        AgentActivityMonitor.shared.preview()
        func page(_ tab: CodingPanel.Tab, _ name: String, shell other: QuickShell? = nil, whileShowing change: (() -> Void)? = nil) {
            UserDefaults.standard.set(tab.rawValue, forKey: "terminal.tab")
            render(TerminalPageCapture(shell: other ?? shell),
                   to: directory.appendingPathComponent(name + ".png"), size: NSSize(width: 740, height: 310),
                   whileShowing: change)
        }
        for family: ThemeFamily in [.macspaces, .midnight, .everforest] {
            ThemeStore.shared.selectFamily(family)
            store.setPreview(packages: packages, listsUpdated: updated)
            page(.homebrew, "homebrew-outdated-\(family.rawValue)")
            page(.shell, "terminal-rail-shell-\(family.rawValue)")
        }
        // Shell when the theme changes while it shows, and a shell first shown after a change.
        for family: ThemeFamily in [.midnight, .everforest] {
            ThemeStore.shared.selectFamily(.macspaces)
            page(.shell, "terminal-shell-switch-\(family.rawValue)") { ThemeStore.shared.selectFamily(family) }
            ThemeStore.shared.selectFamily(family)
            page(.shell, "terminal-shell-fresh-\(family.rawValue)", shell: QuickShell(defaults: UserDefaults(suiteName: "FeatureQA.homebrew")!))
        }
        ThemeStore.shared.selectFamily(.macspaces)
        page(.agents, "terminal-rail-agents")
        precondition(store.outdatedCount == 4, "The rail counts outdated packages, pinned ones included")
        let current = packages.map { package($0.kind, $0.name, $0.title, $0.latest) }
        store.setPreview(packages: current, listsUpdated: updated)
        page(.homebrew, "homebrew-current")
        precondition(store.outdatedCount == 0)
        var running = HomebrewStore.Job(command: .upgradeAll)
        running.log = "==> Upgrading 3 outdated packages:\nnode 24.9.0 -> 24.11.1\ngh 2.81.0 -> 2.83.0\n==> Pouring gh--2.83.0.arm64_tahoe.bottle.tar.gz"
        store.setPreview(packages: packages, job: running, listsUpdated: updated)
        page(.homebrew, "homebrew-running")
        var password = HomebrewStore.Job(command: .upgrade(packages.first { $0.kind == .cask }!))
        password.log = "==> Upgrading visual-studio-code\nsudo: a terminal is required to read the password"
        password.running = false; password.exitCode = 1
        precondition(password.needsPassword)
        store.setPreview(packages: packages, job: password, listsUpdated: updated)
        page(.homebrew, "homebrew-password")
        store.setPreview(packages: [], status: .missing)
        page(.homebrew, "homebrew-missing")
        UserDefaults.standard.set(CodingPanel.Tab.shell.rawValue, forKey: "terminal.tab")
        print("Homebrew and Terminal rail captures written")
    }

    /// Every Terminal tab in the open Nook, so the page's insets are the real ones:
    /// with synthetic data (`terminal-<tab>.png`), then each empty state
    /// (`terminal-<tab>-empty.png`: no sessions, Agents off, no logs, no GitHub
    /// account, no servers with and without earlier dev commands, Homebrew missing).
    static func captureTerminalTabs(to directory: URL) {
        ThemeStore.shared.selectFamily(.macspaces)
        let settings = NookSettings.shared
        settings.resetToDefaults()
        let model = NotchViewModel(geometry: .synthetic, availableWidth: 1440, settings: settings,
            shelf: ShelfStore.shared, nowPlaying: AppServices.shared.nowPlaying,
            powerMonitor: AppServices.shared.powerMonitor, timerService: AppServices.shared.timerService,
            bluetoothMonitor: AppServices.shared.bluetooth, systemActivityMonitor: AppServices.shared.systemActivity,
            teleprompter: AppServices.shared.teleprompter)
        model.state = .expanded
        model.selectedTab = .terminal
        let shell = AppServices.shared.quickShell
        func capture(_ tab: CodingPanel.Tab, _ name: String) {
            UserDefaults.standard.set(tab.rawValue, forKey: "terminal.tab")
            let size = model.expandedSize
            render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent(name + ".png"),
                   size: NSSize(width: size.width + 40, height: size.height + 50))
        }
        let history = ["git status", "cd ~/Projects/Lighthouse && npm run dev", "swift build", "python3 -m http.server 8000", "ls"]
        shell.setPreviewHistory(history)
        precondition(DevServers.startCommands(in: history) == ["python3 -m http.server 8000", "cd ~/Projects/Lighthouse && npm run dev"],
                     "Servers offers the dev commands from the shell's history, newest first")
        CodingStats.shared.preview()
        AgentActivityMonitor.shared.preview()
        HomebrewStore.shared.setPreview(packages: [
            HomebrewPackage(kind: .formula, name: "node", title: "node", installed: "24.9.0", latest: "24.11.1", outdated: true, pinned: false, autoUpdates: false),
            HomebrewPackage(kind: .formula, name: "git", title: "git", installed: "2.51.2", latest: "2.51.2", outdated: false, pinned: false, autoUpdates: false),
        ], listsUpdated: Date().addingTimeInterval(-3600))
        DevServers.preview = [
            DevServers.Server(pid: 101, port: 3000, command: "node", folder: "/Users/sample/Projects/Lighthouse"),
            DevServers.Server(pid: 102, port: 5173, command: "vite", folder: "/Users/sample/Projects/Garden"),
            DevServers.Server(pid: 103, port: 8000, command: "python3", folder: "/Users/sample/Projects/Atlas"),
        ]
        for tab in CodingPanel.Tab.allCases { capture(tab, "terminal-\(tab.rawValue)") }
        AgentActivityMonitor.shared.previewEmpty(enabled: true)
        capture(.agents, "terminal-agents-empty")
        AgentActivityMonitor.shared.previewEmpty(enabled: false)
        capture(.agents, "terminal-agents-off")
        CodingStats.shared.previewEmpty()
        capture(.today, "terminal-today-empty")
        capture(.usage, "terminal-usage-empty")
        capture(.github, "terminal-github-empty")
        DevServers.preview = []
        capture(.servers, "terminal-servers-empty")
        shell.setPreviewHistory([])
        capture(.servers, "terminal-servers-empty-no-history")
        HomebrewStore.shared.setPreview(packages: [], status: .missing)
        capture(.homebrew, "terminal-homebrew-missing")
        DevServers.preview = nil
        UserDefaults.standard.set(CodingPanel.Tab.shell.rawValue, forKey: "terminal.tab")
        model.collapse()
        print("Terminal tab captures written")
    }

    /// A notch (185×32) and the synthetic pill closed at rest, closed with a timer lane,
    /// and open on Home and Music, on a transparent canvas: run on two builds, the files
    /// must match byte for byte when a change keeps today's Macs as they are.
    static func captureNotchShapes(to directory: URL) {
        ThemeStore.shared.selectFamily(.macspaces)
        NookSettings.shared.widgets = [.media, .clock, .timer]
        for (name, geometry) in [("notch", NotchGeometry(width: 185, height: 32, isHardwareNotch: true)),
                                 ("notchless", NotchGeometry.synthetic)] {
            let model = shapeModel(geometry)
            AppServices.shared.timerService.setPreview(remaining: 0, total: 1500)
            render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("\(name)-closed.png"),
                   size: NSSize(width: 480, height: 80))
            AppServices.shared.timerService.setPreview(remaining: 754, total: 1500)
            render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("\(name)-lanes.png"),
                   size: NSSize(width: 480, height: 80))
            model.state = .expanded
            for page: NotchTab in [.nook, .music] {
                model.selectedTab = page
                let size = model.expandedSize
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("\(name)-open-\(page.rawValue).png"),
                       size: NSSize(width: size.width + 52, height: size.height + 28))
            }
        }
        print("Notch shape captures written")
    }

    private static func shapeModel(_ geometry: NotchGeometry) -> NotchViewModel {
        NotchViewModel(geometry: geometry, availableWidth: 1512, settings: NookSettings.shared, shelf: ShelfStore.shared,
                       nowPlaying: AppServices.shared.nowPlaying, powerMonitor: AppServices.shared.powerMonitor,
                       timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                       systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: AppServices.shared.teleprompter)
    }

    /// The island on a simulated cutout (there's no PROLED Mac to capture on): a pill
    /// (120×24, 5 pt below the top edge) and a hole-punch (12×12, 8 pt down), drawn in
    /// dark grey so the capsule's fit shows, under a light wallpaper and menu bar. Closed
    /// at rest, with a timer lane, with the agent bubble beside it, open on Home and Music,
    /// and the open and close morphs as frames (`<name>-morph/`, 30 fps, 2x pixels).
    static func captureIslandShapes(to directory: URL) {
        ThemeStore.shared.selectFamily(.macspaces)
        NookSettings.shared.widgets = [.media, .clock, .timer]
        NookSettings.shared.expandOnHover = false
        AgentActivityMonitor.shared.preview()
        AgentPopout.shared.setPreview(AgentActivityMonitor.shared.sessions.filter { $0.id == "b" })
        let menuBar: CGFloat = 30
        for (name, cutout) in [("pill", CGRect(x: 0, y: 5, width: 120, height: 24)),
                               ("hole", CGRect(x: 0, y: 8, width: 12, height: 12))] {
            let geometry = NotchGeometry.resolve(.init(screenWidth: 1512, safeTop: 0, menuBarHeight: menuBar,
                                                       hasCameraIsland: true, islandCutout: cutout))
            precondition(geometry.isIsland && geometry.isHardwareNotch, "A simulated cutout makes an island")
            let model = shapeModel(geometry)
            func stage(_ size: NSSize, bubble: Bool = false) -> some View {
                let screen = CGRect(origin: .zero, size: size)
                model.screenFrame = screen
                let closed = model.closedNotchFrame ?? .zero
                let popout = AgentPopoutLayout.frame(besideNotch: closed, on: screen)
                return ZStack(alignment: .top) {
                    LinearGradient(colors: [Color(red: 0.78, green: 0.84, blue: 0.93), Color(red: 0.93, green: 0.86, blue: 0.80)],
                                   startPoint: .top, endPoint: .bottom)
                    Rectangle().fill(Color.white.opacity(0.35)).frame(height: menuBar)
                    NotchContainerView(viewModel: model)
                    // The simulated hole, where the hardware would be.
                    Capsule().fill(Color(white: 0.16))
                        .frame(width: cutout.width, height: cutout.height)
                        .offset(y: cutout.minY)
                    if bubble {
                        AgentPopoutView(popout: AgentPopout.shared, stillPulse: 0.6)
                            .frame(width: popout.width, height: popout.height)
                            .position(x: popout.midX, y: screen.maxY - popout.midY)
                    }
                }
                .frame(width: size.width, height: size.height)
            }
            let strip = NSSize(width: 520, height: 64)
            AppServices.shared.timerService.setPreview(remaining: 0, total: 1500)
            render(stage(strip), to: directory.appendingPathComponent("island-\(name)-closed.png"), size: strip)
            AppServices.shared.timerService.setPreview(remaining: 754, total: 1500)
            render(stage(strip), to: directory.appendingPathComponent("island-\(name)-lanes.png"), size: strip)
            render(stage(strip, bubble: true), to: directory.appendingPathComponent("island-\(name)-agent.png"), size: strip)
            AppServices.shared.timerService.setPreview(remaining: 0, total: 1500)
            model.state = .expanded
            var open = NSSize.zero
            for page: NotchTab in [.nook, .music] {
                model.selectedTab = page
                open = NSSize(width: model.expandedSize.width + 52,
                              height: model.expandedSize.height + 38)
                render(stage(open), to: directory.appendingPathComponent("island-\(name)-open-\(page.rawValue).png"), size: open)
            }
            model.state = .collapsed
            captureMorph(stage(open), model: model, size: open, to: directory.appendingPathComponent("island-\(name)-morph"))
        }
        print("Island shape captures written")
    }

    /// Before and after for the closed Nook's look: `solid` (today) and `clear` (nothing
    /// over the camera, activities as bubbles), on a notch, a notchless screen (hint on
    /// and off) and a simulated island, under a light menu bar with the hardware drawn on
    /// top. Each at rest, with a song alone, with music and a timer, and with the agent bubble too,
    /// Keep Awake alone (with 42 minutes left, `awake-timed`; with no limit, `awake`) and beside a
    /// timer (`awake-timer`), plus the open Music page. Files: `looks/<cutout>-<look>-<state>.png`.
    static func captureNotchLooks(to directory: URL) {
        let output = directory.appendingPathComponent("looks", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        ThemeStore.shared.selectFamily(.macspaces)
        NookSettings.shared.widgets = [.media, .clock, .timer]
        NookSettings.shared.showMusicLiveActivity = true
        NookSettings.shared.showTimerLiveActivity = true
        NookSettings.shared.showKeepAwakeLiveActivity = true
        AgentActivityMonitor.shared.preview()
        AgentPopout.shared.setPreview(AgentActivityMonitor.shared.sessions.filter { $0.id == "b" })
        let keepAwake = AppServices.shared.keepAwake
        defer { keepAwake.stop() }
        let cover = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.98, green: 0.55, blue: 0.35, alpha: 1),
                                NSColor(red: 0.42, green: 0.25, blue: 0.62, alpha: 1)])?.draw(in: rect, angle: -60)
            NSColor(white: 1, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 70, y: 66, width: 30, height: 30)).fill()
            return true
        }
        func play(_ playing: Bool) {
            var track = NowPlayingInfo()
            track.title = "Golden Hour"; track.artist = "Sample Artist"; track.sourceName = "Music"
            track.isPlaying = playing; track.duration = 240; track.elapsed = 150; track.artwork = cover
            AppServices.shared.nowPlaying.setPreviewInfo(track)
        }
        let menuBar: CGFloat = 32
        let cutouts: [(String, NotchGeometry.Reading)] = [
            ("notch", .init(screenWidth: 1512, safeTop: 32, auxiliaryLeft: 663.5, auxiliaryRight: 663.5)),
            ("notchless", .init(screenWidth: 1512, safeTop: 0, menuBarHeight: menuBar)),
            ("island", .init(screenWidth: 1512, safeTop: 0, menuBarHeight: menuBar, hasCameraIsland: true,
                             islandCutout: CGRect(x: 0, y: 5, width: 120, height: 24))),
        ]
        var looks: [(String, NotchGeometry.Look, Bool)] = [("solid", .solid, true), ("clear", .clear, true)]
        looks.append(("clear-nohint", .clear, false))
        for (name, reading) in cutouts {
            for (lookName, look, hint) in looks where hint || name == "notchless" {
                let geometry = NotchGeometry.resolve(reading, look: look, notchlessHint: hint)
                let model = shapeModel(geometry)
                func stage(_ size: NSSize, bubble: Bool = false) -> some View {
                    let screen = CGRect(origin: .zero, size: size)
                    model.screenFrame = screen
                    let agent = AgentPopoutLayout.frame(besideNotch: model.closedNotchFrame ?? .zero, on: screen)
                    return ZStack(alignment: .top) {
                        LinearGradient(colors: [Color(red: 0.78, green: 0.84, blue: 0.93), Color(red: 0.93, green: 0.86, blue: 0.80)],
                                       startPoint: .top, endPoint: .bottom)
                        Rectangle().fill(Color.white.opacity(0.35)).frame(height: menuBar)
                        NotchContainerView(viewModel: model)
                        // The hardware, which is black whatever is drawn over it.
                        switch geometry.cutout {
                        case .notch:
                            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(Color.black)
                                .frame(width: geometry.width, height: geometry.height)
                        case .island:
                            Capsule().fill(Color.black).frame(width: 120, height: 24).offset(y: 5)
                        case .none:
                            EmptyView()
                        }
                        if bubble {
                            AgentPopoutView(popout: AgentPopout.shared, stillPulse: 0.6)
                                .frame(width: agent.width, height: agent.height)
                                .position(x: agent.midX, y: screen.maxY - agent.midY)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                }
                let strip = NSSize(width: 560, height: 64)
                let prefix = "\(name)-\(lookName)"
                play(false)
                AppServices.shared.timerService.setPreview(remaining: 0, total: 1500)
                render(stage(strip), to: output.appendingPathComponent("\(prefix)-rest.png"), size: strip)
                guard lookName != "clear-nohint" else { continue }
                play(true)
                render(stage(strip), to: output.appendingPathComponent("\(prefix)-music.png"), size: strip)
                AppServices.shared.timerService.setPreview(remaining: 754, total: 1500)
                render(stage(strip), to: output.appendingPathComponent("\(prefix)-activities.png"), size: strip)
                render(stage(strip, bubble: true), to: output.appendingPathComponent("\(prefix)-agent.png"), size: strip)
                play(false)
                keepAwake.setPreview(remaining: 42 * 60 + 7, total: 3600)
                render(stage(strip), to: output.appendingPathComponent("\(prefix)-awake-timer.png"), size: strip)
                AppServices.shared.timerService.setPreview(remaining: 0, total: 1500)
                render(stage(strip), to: output.appendingPathComponent("\(prefix)-awake-timed.png"), size: strip)
                keepAwake.setPreview(remaining: nil)
                render(stage(strip), to: output.appendingPathComponent("\(prefix)-awake.png"), size: strip)
                keepAwake.stop()
                AppServices.shared.timerService.setPreview(remaining: 0, total: 1500)
                model.state = .expanded
                model.selectedTab = .nook
                let open = NSSize(width: model.expandedSize.width + 52, height: model.expandedSize.height + 38)
                render(stage(open), to: output.appendingPathComponent("\(prefix)-open.png"), size: open)
            }
        }
        print("Notch look captures written")
    }

    /// Opens and closes `model` inside `view`, writing a frame every 1/30 s as it happens.
    private static func captureMorph<V: View>(_ view: V, model: NotchViewModel, size: NSSize, to frames: URL) {
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let start = Date()
        for n in 0..<48 {
            if n == 3 { model.expand(to: .music) }
            if n == 27 { model.collapse() }
            RunLoop.main.run(until: start.addingTimeInterval(Double(n) / 30))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?
                .write(to: frames.appendingPathComponent(String(format: "f%02d.png", n)))
        }
        window.close()
    }

    /// The website's clip of the agent pop-out, built from the app's own views: the shared demo
    /// profile (`WebsiteDemoProfile`: the Clear look, its song and timer) on the Agents video's
    /// stage and close framing, the real closed notch (`NotchContainerView`) with its bubbles, and
    /// the agent bubble (`AgentPopoutView`, the agent's app icon in a black circle) sliding out
    /// from under the notch's edge where `AgentPopoutLayout` puts it, breathing twice and tucking
    /// back, as 1640×940 PNG frames at 30 fps (encoded off the runner) plus a poster. The agent's
    /// icon comes from `MACSPACES_DEMO_AGENT_ICONS` when set, else the app's own fallback.
    static func captureAgentPopoutClip(to directory: URL) {
        let frames = directory.appendingPathComponent("frames")
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let stage = WebsiteDemoAgents.stage
        WebsiteDemoProfile.apply(theme: .nightBlossom, keepAwake: nil)
        defer { WebsiteDemoProfile.finish() }
        WebsiteDemoProfile.play(WebsiteDemoProfile.environmentTrack ?? WebsiteDemoProfile.homeTrack)
        if let icons = ProcessInfo.processInfo.environment["MACSPACES_DEMO_AGENT_ICONS"],
           let icon = WebsiteDemoAgents.macIcon("\(icons)/claude.png") {
            AgentActivityMonitor.previewAgentIcons["claude"] = icon
        }
        defer { AgentActivityMonitor.previewAgentIcons = [:] }
        let popout = AgentPopout.shared
        popout.setPreview([WebsiteDemoAgents.waiting(Date())])
        let model = WebsiteDemoProfile.model(availableWidth: stage.width)
        let screen = CGRect(origin: .zero, size: stage)
        model.screenFrame = screen
        let notch = model.closedNotchFrame ?? .zero
        let target = AgentPopoutLayout.frame(besideNotch: notch, on: screen)
        let tucked = AgentPopoutLayout.startFrame(besideNotch: notch)
        let slideState = SlideState()
        let view = ZStack(alignment: .topLeading) {
            Image(WebsiteDemoProfile.wallpaper(for: .nightBlossom)).resizable().scaledToFill()
                .overlay(Color.black.opacity(0.12))
                .frame(width: stage.width, height: stage.height).clipped()
            DemoMenuBar(height: model.geometry.height, within: WebsiteDemoAgents.wide.minX...WebsiteDemoAgents.wide.maxX, sparse: true)
                .frame(width: stage.width)
            NotchContainerView(viewModel: model)
                .frame(width: stage.width, height: stage.height, alignment: .top)
            // The hardware, which is black whatever is drawn over it.
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(Color.black)
                .frame(width: model.geometry.width, height: model.geometry.height)
                .frame(width: stage.width, alignment: .top)
            SlidingAgentBubble(popout: popout, state: slideState, target: target, tucked: tucked, height: stage.height)
        }
        .frame(width: stage.width, height: stage.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: stage)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        func write(_ url: URL) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            try? WebsiteDemoNotch.capture(host, crop: WebsiteDemoAgents.tight)?
                .representation(using: .png, properties: [:])?.write(to: url)
        }
        // 0.4 s waiting, 0.38 s out on `AgentPopout.show`'s curve, two breaths (3.2 s), 0.22 s
        // back, a beat: 4.8 s, looping.
        let fps = 30.0, total = 144
        for index in 0..<total {
            let t = Double(index) / fps
            let slide: Double
            switch t {
            case ..<0.4: slide = 0
            case ..<0.78: slide = WebsiteDemoAgents.bezier((t - 0.4) / 0.38, 0.2, 0.9, 0.25, 1.05)
            case ..<4.0: slide = 1
            case ..<4.22: slide = 1 - WebsiteDemoAgents.bezier((t - 4.0) / 0.22, 0.42, 0, 0.58, 1)
            default: slide = 0
            }
            slideState.slide = slide
            slideState.time = t >= 0.4 ? t - 0.4 : 0
            write(frames.appendingPathComponent(String(format: "frame-%03d.png", index)))
        }
        slideState.slide = 1; slideState.time = WebsiteDemoAgents.posterAt - WebsiteDemoAgents.outAt
        write(directory.appendingPathComponent("agent-popout-poster.png"))
        window.contentView = nil
    }

    private final class SlideState: ObservableObject {
        @Published var slide = 0.0
        @Published var time = 0.0
    }

    /// The agent bubble where its panel would be (the panel is hidden from captures).
    private struct SlidingAgentBubble: View {
        @ObservedObject var popout: AgentPopout
        @ObservedObject var state: SlideState
        let target: CGRect, tucked: CGRect, height: CGFloat

        var body: some View {
            let x = tucked.midX + (target.midX - tucked.midX) * state.slide
            AgentPopoutView(popout: popout, stillTime: state.time)
                .frame(width: target.width, height: target.height)
                .opacity(min(1, max(0, state.slide)))
                .position(x: x, y: height - target.midY)
        }
    }

    /// The process's CPU time so far, user and system.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    /// CPU while the open Nook's Music page plays in Blossom (a song, lyrics, the
    /// scrubber and the flower scene), with the flowers in Core Animation and then in
    /// the old Canvas timeline. Needs a window on screen, so it runs on CI's Macs.
    static func measureMotionCost(to directory: URL) {
        let theme = ThemeStore.shared
        theme.selectFamily(.blossom)
        let player = NowPlayingController()
        var track = NowPlayingInfo()
        track.title = "Harbour Lights - 2011 Remaster"; track.artist = "Sample Artist"; track.album = "Low Tide"
        track.sourceName = "Music"; track.capabilities = [.playPause, .previous, .next, .seek]
        track.duration = 236; track.elapsed = 81; track.isPlaying = true
        player.setPreviewInfo(track)
        let lyrics = TeleprompterService(nowPlaying: player)
        lyrics.setPreview(current: "Hold the evening light a little longer", upcoming: "Till the harbour lamps come on", source: .lyrics)
        MotifImages.shared.prepare(.petals)
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        var report: [String] = []
        for (label, layered) in [("Core Animation", true), ("Canvas timeline", false)] {
            ThemeMotifView.flowersUseCoreAnimation = layered
            let page = ZStack {
                theme.notch.surface
                ThemeMotifView(motif: .petals, accent: theme.notch.accent, ink: theme.nookForeground, animated: true)
                MediaPlayerView(nowPlaying: player, largeArtwork: true, lyricsService: lyrics).padding(.top, 20)
            }
            .frame(width: 620, height: 346)
            .foregroundStyle(theme.nookForeground)
            .environment(\.colorScheme, .dark)
            let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 620, height: 346), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: page)
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            let start = cpuSeconds()
            RunLoop.main.run(until: Date().addingTimeInterval(10))
            let line = String(format: "motion-cost Blossom Music page, flowers in %@: %.1f%% CPU over 10 s",
                              label, (cpuSeconds() - start) / 10 * 100)
            print(line)
            report.append(line)
            window.orderOut(nil)
            window.contentView = nil
        }
        ThemeMotifView.flowersUseCoreAnimation = true
        try? report.joined(separator: "\n").write(to: directory.appendingPathComponent("motion-cost.txt"), atomically: true, encoding: .utf8)
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    static func captureIfRequested() -> Bool {
        guard let output = ProcessInfo.processInfo.environment["MACSPACES_FEATURE_QA"] else { return false }
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.FeatureQA")
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        InteractionRegressionChecks.run()
        DeviceRegressionChecks.run()
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "perf" {
            // Times a full layout and draw of the heaviest Settings and Music views.
            func time<V: View>(_ label: String, _ size: NSSize, _ view: () -> V) {
                let host = NSHostingView(rootView: view().environment(\.colorScheme, .dark))
                host.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                let start = CFAbsoluteTimeGetCurrent()
                host.layoutSubtreeIfNeeded(); host.display()
                let first = (CFAbsoluteTimeGetCurrent() - start) * 1000
                let again = CFAbsoluteTimeGetCurrent()
                host.rootView = view().environment(\.colorScheme, .dark)
                host.layoutSubtreeIfNeeded(); host.display()
                print(String(format: "perf %-28@ first %7.1f ms  redraw %6.1f ms", label as NSString, first, (CFAbsoluteTimeGetCurrent() - again) * 1000))
            }
            let theme = ThemeStore.shared
            for style in LyricStyle.allCases {
                time("lyric \(style.rawValue)", NSSize(width: 200, height: 96)) {
                    StyledLyricView(style: style, current: "Hold the evening light a little longer", upcoming: "Till the harbour lamps come on",
                                    accent: theme.notch.accent, ink: theme.nookForeground, animated: false, progress: 0.55)
                }
            }
            time("lyric picker (open)", NSSize(width: 700, height: 500)) { LyricStylePicker() }
            // The Music page with lyrics, in each lyric style, as a theme with a photo.
            theme.selectFamily(.blossom)
            let player = NowPlayingController()
            var track = NowPlayingInfo()
            track.title = "Harbour Lights"; track.artist = "Sample Artist"; track.album = "Low Tide"
            track.sourceName = "Music"; track.capabilities = [.playPause, .previous, .next, .seek]
            track.duration = 236; track.elapsed = 81; track.isPlaying = true
            player.setPreviewInfo(track)
            let lyrics = TeleprompterService(nowPlaying: player)
            lyrics.setPreview(current: "Hold the evening light a little longer", upcoming: "Till the harbour lamps come on", source: .lyrics)
            for style in LyricStyle.allCases {
                theme.lyricStyle = style
                time("music page \(style.rawValue)", NSSize(width: 532, height: 272)) {
                    MediaPlayerView(nowPlaying: player, largeArtwork: true, lyricsService: lyrics).frame(width: 532, height: 272)
                }
            }
            // Decoding every theme photo at full size, as the cards did.
            let decode = CFAbsoluteTimeGetCurrent()
            var decoded = 0
            for motif in ThemeMotif.allCases {
                guard let asset = motif.floralAsset ?? motif.natureAsset,
                      let image = Bundle.main.image(forResource: asset)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                context?.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
                decoded += 1
            }
            print(String(format: "perf decode %d theme photos       %7.1f ms", decoded, (CFAbsoluteTimeGetCurrent() - decode) * 1000))
            NookThemePicker.startsFullyOpen = true
            time("theme picker (all open)", NSSize(width: 700, height: 2400)) { NookThemePicker() }
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            time("theme picker, thumbnails warm", NSSize(width: 700, height: 2400)) { NookThemePicker() }
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "clock-page" {
            // A pin left over from the Map tile must not show on the Clock page.
            let options = WidgetOptions.shared
            options.clockPlaces = ["America/Chicago", "Asia/Tokyo", "Europe/London"]
            options.clockPin = WidgetOptions.ClockPin(latitude: -15.4, longitude: 28.3, zone: "Africa/Lusaka",
                                                      name: "Western", country: "Zambia")
            render(ClockPage().frame(width: 760, height: 300).background(ThemeStore.shared.notch.surface)
                    .foregroundStyle(ThemeStore.shared.nookForeground).environment(\.colorScheme, .dark),
                   to: directory.appendingPathComponent("clock-page.png"), size: NSSize(width: 760, height: 300))
            // Five places, long names included, two of them chosen for Match up.
            options.clockPlaces = ["America/Chicago", "Asia/Tokyo", "Pacific/Pitcairn",
                                   WidgetOptions.namedPlace(zone: "Africa/Lusaka", name: "Western", latitude: -15.4, longitude: 28.3),
                                   "Europe/London"]
            render(ClockPage(previewSelection: ["Asia/Tokyo", "Europe/London"]).frame(width: 760, height: 300)
                    .background(ThemeStore.shared.notch.surface)
                    .foregroundStyle(ThemeStore.shared.nookForeground).environment(\.colorScheme, .dark),
                   to: directory.appendingPathComponent("clock-page-full.png"), size: NSSize(width: 760, height: 300))
            render(ClockPage(previewSelection: ["Europe/London"], previewMatching: true).frame(width: 760, height: 300)
                    .background(ThemeStore.shared.notch.surface)
                    .foregroundStyle(ThemeStore.shared.nookForeground).environment(\.colorScheme, .dark),
                   to: directory.appendingPathComponent("clock-page-match.png"), size: NSSize(width: 760, height: 300))
            render(ClockPage(previewSelection: ["Asia/Tokyo", "Europe/London"], previewMatching: true).frame(width: 760, height: 300)
                    .background(ThemeStore.shared.notch.surface)
                    .foregroundStyle(ThemeStore.shared.nookForeground).environment(\.colorScheme, .dark),
                   to: directory.appendingPathComponent("clock-page-match-far.png"), size: NSSize(width: 760, height: 300))
            // Towns clicked close together in one time zone: all listed, labels kept apart.
            options.clockPlaces = ["America/Chicago",
                                   WidgetOptions.namedPlace(zone: "America/Denver", name: "Dupree", latitude: 45.05, longitude: -101.6),
                                   WidgetOptions.namedPlace(zone: "America/Chicago", name: "Loup City", latitude: 41.28, longitude: -98.97),
                                   WidgetOptions.namedPlace(zone: "America/Chicago", name: "Jasper", latitude: 30.92, longitude: -94.0),
                                   WidgetOptions.namedPlace(zone: "America/Chicago", name: "Wichita", latitude: 37.69, longitude: -97.34),
                                   "Asia/Tokyo"]
            render(ClockPage(previewFocus: "America/Chicago").frame(width: 760, height: 300)
                    .background(ThemeStore.shared.notch.surface)
                    .foregroundStyle(ThemeStore.shared.nookForeground).environment(\.colorScheme, .dark),
                   to: directory.appendingPathComponent("clock-page-cluster.png"), size: NSSize(width: 760, height: 300))
            options.clockPin = nil
            // The Calendar page's Life view: asking for a birthday, then a life in weeks.
            let birthday = options.birthday
            options.birthday = nil
            render(LifeView().frame(width: 580, height: 290).padding(.horizontal, 22).background(ThemeStore.shared.notch.surface)
                    .foregroundStyle(ThemeStore.shared.nookForeground).environment(\.colorScheme, .dark),
                   to: directory.appendingPathComponent("life-setup.png"), size: NSSize(width: 624, height: 290))
            options.birthday = Calendar.current.date(byAdding: .day, value: -12_800, to: Date())
            render(LifeView().frame(width: 580, height: 290).padding(.horizontal, 22).background(ThemeStore.shared.notch.surface)
                    .foregroundStyle(ThemeStore.shared.nookForeground).environment(\.colorScheme, .dark),
                   to: directory.appendingPathComponent("life.png"), size: NSSize(width: 624, height: 290))
            render(LifeView(previewEditing: true).frame(width: 580, height: 290).padding(.horizontal, 22).background(ThemeStore.shared.notch.surface)
                    .foregroundStyle(ThemeStore.shared.nookForeground).environment(\.colorScheme, .dark),
                   to: directory.appendingPathComponent("life-editor.png"), size: NSSize(width: 624, height: 290))
            ThemeStore.shared.selectFamily(.blossom)
            render(CalendarAppView(service: AppServices.shared.calendar).frame(width: 620, height: 300).background(ThemeStore.shared.notch.surface)
                    .foregroundStyle(ThemeStore.shared.nookForeground).environment(\.colorScheme, ThemeStore.shared.notch.colorScheme),
                   to: directory.appendingPathComponent("calendar-page.png"), size: NSSize(width: 620, height: 300))
            render(LifeView().frame(width: 580, height: 290).padding(.horizontal, 22).background(ThemeStore.shared.notch.surface)
                    .foregroundStyle(ThemeStore.shared.nookForeground).environment(\.colorScheme, ThemeStore.shared.notch.colorScheme),
                   to: directory.appendingPathComponent("life-blossom.png"), size: NSSize(width: 624, height: 290))
            ThemeStore.shared.selectFamily(.macspaces)
            options.birthday = birthday
            print("Clock page capture written")
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "power-permissions" {
            // The Battery row in every state, and the Cable management card in each of its
            // cases, all synthetic: nothing reads this Mac's battery, charger or SMC.
            ThemeStore.shared.selectFamily(.macspaces)
            let surface = ThemeStore.shared.notch.surface
            let now = Date()
            let good = BatteryHealth(maximumCapacity: 87, conditionNormal: true, fetchedAt: now)
            let adapter = ChargerInfo(name: "140W USB-C Power Adapter", connectionWatts: 140, ratedWatts: 140)
            let cables: [(BatteryState, ChargerInfo?, ChargerInfo?, Bool, Int?, String?, Bool, Bool)] = [
                (.onBattery, nil, adapter, false, nil, nil, false, true),
                (.charging, ChargerInfo(name: ChargerInfo.placeholderName, connectionWatts: nil, ratedWatts: nil), nil, true, nil, nil, false, true),
                (.charging, adapter, nil, false, nil, nil, false, true),
                (.charging, adapter, nil, false, 32, "28 V", false, true),
                (.charging, ChargerInfo(name: "140W USB-C Power Adapter", connectionWatts: 60, ratedWatts: 140), nil, false, 60, "20 V", true, true),
                (.notCharging, adapter, nil, false, nil, nil, false, false),
                (.draining, ChargerInfo(name: "30W USB-C Power Adapter", connectionWatts: 30, ratedWatts: 30), nil, false, 30, "15 V", true, true),
                (.fullyCharged, adapter, nil, false, 12, "20 V", false, true),
            ]
            let cards: [PowerSourceMonitor] = cables.map { cable in
                let monitor = PowerSourceMonitor()
                monitor.setPreview(state: cable.0, level: cable.0 == .fullyCharged ? 100 : 64, minutesToEmpty: 320, onBatterySince: now.addingTimeInterval(-4200),
                                   health: good, cycles: 343, charger: cable.1, lastCharger: cable.2, readingCharger: cable.3)
                monitor.input.setPreview(watts: cable.4, step: cable.5, atLimit: cable.6, isLive: cable.7)
                return monitor
            }
            render(HStack(alignment: .top, spacing: 12) {
                ForEach(cards.indices, id: \.self) { index in
                    VStack(spacing: 10) {
                        CableManagementCard(power: cards[index], input: cards[index].input, bluetooth: BluetoothMonitor())
                        SystemBatteryRing(power: cards[index]).padding(.horizontal, 11).padding(.top, 60)
                    }
                        .frame(width: 250, height: 300, alignment: .top)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                }
            }
            .padding(12).background(surface).foregroundStyle(ThemeStore.shared.nookForeground).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("cable-card.png"), size: NSSize(width: 8 * 250 + 7 * 12 + 24, height: 324))
            render(ScrollView { VStack(spacing: 16) { WidgetAccessSettings() }.padding(20) }
                    .frame(width: 720).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark),
                   to: directory.appendingPathComponent("permissions.png"), size: NSSize(width: 720, height: 900))
            // The sidebar's Notch group, open on Apps, and at the tiled (icons-only) width.
            SettingsNavigationModel.shared.selection = .apps
            render(SettingsView(), to: directory.appendingPathComponent("settings-apps.png"), size: NSSize(width: 980, height: 760))
            render(SettingsView().frame(width: 520, height: 480), to: directory.appendingPathComponent("settings-apps-tiled.png"),
                   size: NSSize(width: 520, height: 480))
            print("Battery row, cable management and permissions captures written")
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        // `wisp-looks` is the same captures without the CPU measurements.
        if let wispScope = ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"], ["wisp", "wisp-looks"].contains(wispScope) {
            // Wisp's page empty, talking and with no model in Frost, Noir, Blossom, Everforest and
            // Midnight; in the last two its dock toggle on and off, another page's dock (no Wisp
            // button beside Settings); and every mood.
            let settings = NookSettings.shared
            settings.resetToDefaults()
            settings.setDockApp(.wisp, shown: true)   // Wisp ships out of the dock.
            let wisp = WispModel.shared
            let conversation = [
                WispMessage(role: .user, text: "Remind me to call the bank tomorrow at 10"),
                WispMessage(role: .wisp, text: "Added “call the bank” for tomorrow at 10:00."),
                WispMessage(role: .user, text: "What's my day?"),
                WispMessage(role: .wisp, text: "Coming up: Design review at 3:00 PM. Due: Send the invoice, Book the dentist."),
            ]
            // One exchange (it should sit beside the face, not leave a void) and one long enough to scroll.
            let short = Array(conversation.prefix(2))
            let long = conversation + [
                WispMessage(role: .user, text: "Tea timer 4 minutes"),
                WispMessage(role: .wisp, text: "Tea timer set for 4 minutes."),
                WispMessage(role: .user, text: "Note: ask Sam about the venue"),
                WispMessage(role: .wisp, text: "Saved “ask Sam about the venue” to Notes."),
                WispMessage(role: .user, text: "Thanks!"),
                WispMessage(role: .wisp, text: "Any time."),
            ]
            AppServices.shared.calendar.setReminderFixtureRows([
                TodoItem(id: "1", title: "Send the invoice", dueDate: Date()),
                TodoItem(id: "2", title: "Book the dentist", dueDate: nil),
                TodoItem(id: "3", title: "Call the bank", dueDate: Date().addingTimeInterval(86_400)),
            ])
            // Light (Frost), dark (Noir) and three Nature/terminal themes.
            for family in [ThemeFamily.frost, .macspaces, .blossom, .everforest, .midnight] {
                ThemeStore.shared.selectFamily(family)
                let model = NotchViewModel(geometry: .synthetic, availableWidth: 1440, settings: settings,
                    shelf: ShelfStore.shared, nowPlaying: AppServices.shared.nowPlaying,
                    powerMonitor: AppServices.shared.powerMonitor, timerService: AppServices.shared.timerService,
                    bluetoothMonitor: AppServices.shared.bluetooth, systemActivityMonitor: AppServices.shared.systemActivity,
                    teleprompter: AppServices.shared.teleprompter)
                model.state = .expanded
                let size = NSSize(width: model.expandedSize.width + 40, height: model.expandedSize.height + 50)
                let name = family == .macspaces ? "noir" : family.rawValue
                func dock(_ file: String) {
                    render(NotchHeaderView(viewModel: model)
                        .frame(width: 572, height: 54)
                        .foregroundStyle(ThemeStore.shared.nookForeground)
                        .background(ThemeStore.shared.notch.tile),
                        to: directory.appendingPathComponent(file), size: NSSize(width: 572, height: 54))
                }
                model.selectedTab = .wisp
                settings.wispSpeaks = true
                // The tag as it reads with Apple's model, then with none (the runner has none).
                wisp.previewEngine = .appleIntelligence
                wisp.setPreview([], mood: .idle)
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("wisp-\(name)-empty.png"), size: size)
                wisp.setPreview(conversation, mood: .happy)
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("wisp-\(name)-talking.png"), size: size)
                if family == .macspaces || family == .frost {
                    // The big moods, whose eyes reach past their column over the conversation.
                    for (mood, label) in [(WispMood.surprised, "surprised"), (.celebrating, "celebrating"), (.love, "love")] {
                        wisp.setPreview(conversation, mood: mood)
                        render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("wisp-\(name)-talking-\(label).png"), size: size)
                    }
                    wisp.setPreview([], mood: .surprised)
                    render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("wisp-\(name)-empty-surprised.png"), size: size)
                }
                wisp.setPreview(short, mood: .happy)
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("wisp-\(name)-talking-short.png"), size: size)
                wisp.setPreview(long, mood: .idle)
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("wisp-\(name)-talking-long.png"), size: size)
                wisp.previewEngine = .offline("Turn on Apple Intelligence in System Settings to chat in plain language. Requests like “remind me to call Sam tomorrow” work now.")
                wisp.setPreview([], mood: .idle)
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("wisp-\(name)-offline.png"), size: size)
                wisp.setPreview(conversation, mood: .happy)
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("wisp-\(name)-offline-talking.png"), size: size)
                wisp.previewEngine = .appleIntelligence
                guard [.everforest, .midnight].contains(family) else { model.collapse(); continue }
                dock("wisp-\(name)-dock-speaks-on.png")
                settings.wispSpeaks = false
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("wisp-\(name)-talking-speaks-off.png"), size: size)
                dock("wisp-\(name)-dock-speaks-off.png")
                settings.wispSpeaks = true
                // Any other page: Settings, Pin and Close only, and no Wisp controls.
                model.selectedTab = .reminders
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("wisp-\(name)-reminders.png"), size: size)
                dock("wisp-\(name)-dock-reminders.png")
                model.collapse()
            }
            let moods: [WispMood] = [.idle, .listening, .thinking, .speaking, .happy, .surprised, .sleepy, .confused, .love, .celebrating]
            render(HStack(spacing: 14) {
                ForEach(moods, id: \.self) { mood in
                    VStack(spacing: 4) {
                        WispFace(mood: mood, size: 70)
                        Text(String(describing: mood)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(16).background(ThemeStore.shared.notch.surface), to: directory.appendingPathComponent("wisp-moods.png"),
                   size: NSSize(width: 1080, height: 140))
            // The character: moods, props, still poses, a few moments as frames, and its CPU.
            WispCharacterCaptures.capture(to: directory, measuring: wispScope == "wisp")
            wisp.setPreview([], mood: .idle)
            wisp.previewEngine = nil
            settings.resetToDefaults()
            print("Wisp captures written")
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "communication-pages" {
            ThemeStore.shared.selectFamily(.everforest)
            let settings = NookSettings.shared
            settings.resetToDefaults()
            let model = NotchViewModel(geometry: .synthetic, availableWidth: 1440, settings: settings,
                shelf: ShelfStore.shared, nowPlaying: AppServices.shared.nowPlaying,
                powerMonitor: AppServices.shared.powerMonitor, timerService: AppServices.shared.timerService,
                bluetoothMonitor: AppServices.shared.bluetooth, systemActivityMonitor: AppServices.shared.systemActivity,
                teleprompter: AppServices.shared.teleprompter)
            model.state = .expanded
            for connected in [false, true] {
                MeetingControls.shared.setPreview(muted: connected ? true : nil, cameraOff: connected ? false : nil)
                model.selectedTab = .meetings
                let size = model.expandedSize
                render(NotchContainerView(viewModel: model),
                       to: directory.appendingPathComponent(connected ? "meetings-connected.png" : "meetings.png"),
                       size: NSSize(width: size.width + 40, height: size.height + 50))
            }
            model.selectedTab = .dictation
            for filled in [false, true] {
                DictationModel.shared.text = filled ? "Here's the draft from our conversation. I'll share the updated design after reviewing the meeting notes." : ""
                let size = model.expandedSize
                render(NotchContainerView(viewModel: model),
                       to: directory.appendingPathComponent(filled ? "dictation-draft.png" : "dictation.png"),
                       size: NSSize(width: size.width + 40, height: size.height + 50))
            }
            model.collapse()
            print("Communication pages and lyric decoding regression checks passed")
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
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
            print("Dock captures passed: Apple Music playlist, no Spotify device capsule, Home profiles, Settings-only, many profiles")
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
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "clock-preferences" {
            let theme = ThemeStore.shared
            theme.selectFamily(.blossom)
            SettingsNavigationModel.shared.selection = .apps
            render(SettingsView(), to: directory.appendingPathComponent("apps-without-preferences.png"),
                   size: NSSize(width: 1100, height: 900))
            let states: [(BatteryState, Int)] = [(.fullyCharged, 100), (.charging, 64), (.onBattery, 72), (.low, 9), (.draining, 64), (.unavailable, 0)]
            let monitors = states.map { state, level in
                let monitor = PowerSourceMonitor()
                monitor.setPreview(state: state, level: level, minutesToFull: 40, minutesToEmpty: state == .low ? 24 : 318)
                return monitor
            }
            render(HStack(spacing: 18) {
                ForEach(monitors.indices, id: \.self) { index in
                    SystemBatteryRing(power: monitors[index])
                }
            }.padding(20).background(theme.notch.surface).foregroundStyle(theme.nookForeground),
                to: directory.appendingPathComponent("battery-indicators.png"), size: NSSize(width: 400, height: 110))
            print("Simplified settings captures written: Apps without preferences; battery indicators in six states")
            NSApp.terminate(nil)
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "settings-update" {
            Task {
                await SettingsUpdateRegressionChecks.run()
                let theme = ThemeStore.shared
                let settings = NookSettings.shared
                settings.widgets = [.media, .clock, .timer]
                for family: ThemeFamily in [.macspaces, .midnight, .everforest] {
                    theme.selectFamily(family)
                    SettingsNavigationModel.shared.selection = .widgets
                    render(SettingsView(), to: directory.appendingPathComponent("home-" + family.rawValue + ".png"), size: NSSize(width: 1100, height: 1100))
                    SettingsNavigationModel.shared.selection = .appearance
                    render(SettingsView(), to: directory.appendingPathComponent("appearance-" + family.rawValue + ".png"), size: NSSize(width: 1100, height: 850))
                }
                theme.selectFamily(.everforest)
                render(TrayPageView(tray: ShelfStore.shared, isDropTargeted: .constant(false)).padding(20).background(theme.notch.surface).foregroundStyle(theme.nookForeground),
                    to: directory.appendingPathComponent("tray-empty.png"), size: NSSize(width: 620, height: 300))
                SettingsNavigationModel.shared.selection = .apps
                render(SettingsView(), to: directory.appendingPathComponent("apps-settings.png"), size: NSSize(width: 1100, height: 950))
                SettingsNavigationModel.shared.selection = .general
                render(SettingsView(), to: directory.appendingPathComponent("general.png"), size: NSSize(width: 1100, height: 900))
                render(WidgetGallery(settings: settings, select: { _ in }).padding(20).background(theme.notch.surface).foregroundStyle(theme.nookForeground),
                    to: directory.appendingPathComponent("widget-gallery.png"), size: NSSize(width: 920, height: 1100))
                // Album covers' music folder row: a folder chosen (Everforest), then the switch on
                // with none, as kept from before folders were asked for (Midnight). The harness's
                // own defaults domain and a synthetic folder; nothing real is read.
                let musicFolder = FileManager.default.temporaryDirectory.appendingPathComponent("Music Library", isDirectory: true)
                try? FileManager.default.createDirectory(at: musicFolder, withIntermediateDirectories: true)
                let defaults = UserDefaults.standard
                defaults.set(true, forKey: LocalCovers.enabledKey)
                if let bookmark = try? musicFolder.bookmarkData(options: [.withSecurityScope],
                                                                includingResourceValuesForKeys: [.localizedNameKey, .nameKey, .pathKey], relativeTo: nil) {
                    defaults.set(bookmark, forKey: LocalCovers.folderKey)
                }
                theme.selectFamily(.everforest)
                SettingsNavigationModel.shared.selection = .appearance
                render(SettingsView(), to: directory.appendingPathComponent("appearance-music-folder.png"), size: NSSize(width: 1100, height: 1500))
                defaults.removeObject(forKey: LocalCovers.folderKey)
                theme.selectFamily(.midnight)
                render(SettingsView(), to: directory.appendingPathComponent("appearance-music-folder-none.png"), size: NSSize(width: 1100, height: 1500))
                defaults.set(false, forKey: LocalCovers.enabledKey)
                try? FileManager.default.removeItem(at: musicFolder)
                print("Settings captures written: Home, collapsed Appearance, app settings, General, gallery, empty Tray and the music folder row")
                NSApp.terminate(nil)
            }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "standard-pages" {
            ThemeStore.shared.selectFamily(.macspaces)
            let settings = NookSettings.shared
            settings.widgets = [.media, .clock, .timer]
            WidgetOptions.shared.clockStyle = .dot
            let gibibyte = Double(1 << 30)
            AppServices.shared.systemStats.setPreview(memoryUsedBytes: 13.01 * gibibyte, swapUsedBytes: 2.57 * gibibyte,
                                                     diskFreeBytes: 149.185 * gibibyte)
            AppServices.shared.weather.setPreviewSnapshot(.init(temperature: 20, weatherCode: 1, high: 22, low: 12))
            let power = AppServices.shared.powerMonitor
            power.setPreview(state: .charging, level: 64, minutesToFull: 40,
                health: BatteryHealth(maximumCapacity: 87, conditionNormal: true, fetchedAt: Date()), cycles: 343,
                charger: ChargerInfo(name: "140W USB-C Power Adapter", connectionWatts: 140, ratedWatts: 140))
            var track = NowPlayingInfo()
            track.title = "Your music"; track.artist = "Sample Artist"; track.album = "Sample Album"
            track.sourceName = "Music"; track.sourceBundleID = "com.apple.Music"
            track.duration = 240; track.elapsed = 72; track.capabilities = [.playPause, .previous, .next, .seek]
            AppServices.shared.nowPlaying.setPreviewInfo(track)
            AppServices.shared.teleprompter.setPreview(current: "Hold the evening light a little longer", upcoming: "Till the harbour lamps come on", source: .lyrics)
            let qaGeometry = ProcessInfo.processInfo.environment["MACSPACES_QA_HARDWARE_NOTCH"] == "1"
                ? NotchGeometry(width: 185, height: 37, isHardwareNotch: true) : .synthetic
            let model = NotchViewModel(geometry: qaGeometry, availableWidth: 1440, settings: settings,
                shelf: ShelfStore.shared, nowPlaying: AppServices.shared.nowPlaying, powerMonitor: power,
                timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: AppServices.shared.teleprompter)
            model.state = .expanded
            for page: NotchTab in [.nook, .music, .weather, .tray, .system, .clock] {
                model.selectedTab = page
                let size = model.expandedSize
                render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("page-" + page.rawValue + ".png"),
                    size: NSSize(width: size.width + 52, height: size.height + 28))
            }
            print("Standard page captures written: Home regular clock despite Dot page style, Music, Weather, Tray and compact System")
            NSApp.terminate(nil)
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "performance" {
            Task {
                await PerformanceRegressionChecks.run()
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
            ThemeStore.shared.selectFamily(.everforest)
            let files = directory.appendingPathComponent("Fixture files")
            try! FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
            let urls = ["Design.md", "Budget.csv"].map { files.appendingPathComponent($0) } + [URL(fileURLWithPath: "/Volumes/QA Drive/Unavailable.pdf")]
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
            if ProcessInfo.processInfo.environment["MACSPACES_DEMO_THEME"] == "blossom" { ThemeStore.shared.selectFamily(.blossom) }
            Task {
                // A file basket and the Tray page with synthetic files: screenshots,
                // a photo, a PDF, text files and one on a disconnected drive.
                let files = directory.appendingPathComponent("Basket files", isDirectory: true)
                try? FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
                let names = ["Trip itinerary.md", "Budget.csv", "Poster draft.txt"]
                for name in names { try? "Sample\n".write(to: files.appendingPathComponent(name), atomically: true, encoding: .utf8) }
                let today = DateFormatter(); today.dateFormat = "yyyy-MM-dd"
                let shots = ["Screenshot \(today.string(from: Date())) at 14.03.22.png", "Screenshot \(today.string(from: Date())) at 14.05.10.png", "Garden.png"]
                for (index, name) in shots.enumerated() { Self.writeQAPicture(files.appendingPathComponent(name), wide: index < 2, hue: CGFloat(index) * 0.3) }
                let pdf = files.appendingPathComponent("Boarding pass.pdf")
                Self.writeQAPDF(pdf)
                let offline = URL(fileURLWithPath: "/Volumes/QA Drive/Archive.zip")
                for (label, filled) in [("empty", false), ("files", true)] {
                    let store = ShelfStore(basketID: UUID())
                    if filled {
                        store.setPreviewItems([files.appendingPathComponent(shots[0]), files.appendingPathComponent(shots[2]), pdf] + names.prefix(1).map { files.appendingPathComponent($0) }, selectedIndex: 0)
                        await store.waitForFileMetadata()
                    }
                    render(BasketPanelView(manager: BasketWindowController.shared, store: store, basket: FileBasket(name: "Weekend trip"))
                            .frame(width: 380, height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(30)
                            .background { WebsiteBlossomWallpaper() },
                           to: directory.appendingPathComponent("basket-\(label).png"), size: NSSize(width: 440, height: 310))
                    render(BasketBubble(manager: BasketWindowController.shared, store: store, basket: FileBasket(name: "Weekend trip"), open: {})
                            .frame(width: 64, height: 64).padding(28)
                            .background { WebsiteBlossomWallpaper() },
                           to: directory.appendingPathComponent("basket-bubble-\(label).png"), size: NSSize(width: 120, height: 120))
                }
                // The Tray page at the Nook's page size: browsing, a multi-selection
                // with an offline file, the Undo bar after Clear All, and empty.
                let tray = ShelfStore(basketID: UUID())
                tray.setPreviewItems(shots.map { files.appendingPathComponent($0) } + [pdf, offline] + names.map { files.appendingPathComponent($0) })
                await tray.waitForFileMetadata()
                let page = { TrayPageView(tray: tray, isDropTargeted: .constant(false)).frame(width: 600, height: 250).padding(10)
                    .background(ThemeStore.shared.notch.surface).foregroundStyle(ThemeStore.shared.nookForeground).preferredColorScheme(.dark) }
                render(page(), to: directory.appendingPathComponent("tray-page.png"), size: NSSize(width: 620, height: 270))
                tray.select(tray.items[0]); tray.select(tray.items[3], extending: true); tray.select(tray.items[4], extending: true)
                render(page(), to: directory.appendingPathComponent("tray-page-selected.png"), size: NSSize(width: 620, height: 270))
                tray.select(nil); tray.setPreviewStatus(undo: nil, notice: "\u{201C}Screenshot at 14.01.07\u{201D} was deleted, so it left the Tray")
                render(page(), to: directory.appendingPathComponent("tray-page-notice.png"), size: NSSize(width: 620, height: 270))
                tray.setPreviewStatus(undo: nil, notice: nil)
                tray.removeAll()
                render(page(), to: directory.appendingPathComponent("tray-page-undo.png"), size: NSSize(width: 620, height: 270))
                tray.undoRemoval()
                tray.select(tray.items[4])
                render(page(), to: directory.appendingPathComponent("tray-page-offline.png"), size: NSSize(width: 620, height: 270))
                for family: ThemeFamily in [.midnight, .everforest] {
                    ThemeStore.shared.selectFamily(family)
                    tray.select(tray.items[0])
                    render(page(), to: directory.appendingPathComponent("tray-page-\(family.rawValue).png"), size: NSSize(width: 620, height: 270))
                }
                print("Basket and Tray captures written")
                NSApp.terminate(nil)
            }
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
            render(ActivitiesSettingsPane().frame(width: 760, height: 1100),
                   to: directory.appendingPathComponent("settings-activities-255.png"), size: NSSize(width: 760, height: 1100))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "stickers-v2" {
            StickerLyricCaptures.capture(to: directory)
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
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "system-page" {
            // The System page with synthetic stats: graphs, details and the Overtime card.
            let stats = SystemStatsService(); stats.setPreview()
            ThemeStore.shared.selectFamily(.macspaces)
            let power = PowerSourceMonitor()
            power.setPreview(state: .charging, level: 64, minutesToFull: 40,
                             health: BatteryHealth(maximumCapacity: 87, conditionNormal: true, fetchedAt: Date()), cycles: 343,
                             temperatureC: 31, charger: ChargerInfo(name: "140W USB-C Power Adapter", connectionWatts: 140, ratedWatts: 140))
            power.input.setPreview(watts: 32, step: "28 V")
            render(SystemAppView(stats: stats, power: power, bluetooth: BluetoothMonitor(), keepAwake: KeepAwakeService())
                    // Match the real content region inside the standard 620-point shell.
                    .frame(width: 580, height: 314).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("system-page.png"), size: NSSize(width: 580, height: 314))
            let unplugged = PowerSourceMonitor()
            unplugged.setPreview(state: .onBattery, level: 72, minutesToEmpty: 318, onBatterySince: Date().addingTimeInterval(-4200),
                                 health: BatteryHealth(maximumCapacity: 87, conditionNormal: true, fetchedAt: Date()), cycles: 343)
            render(SystemAppView(stats: stats, power: unplugged, bluetooth: BluetoothMonitor(), keepAwake: KeepAwakeService())
                    .frame(width: 580, height: 314).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("system-page-battery.png"), size: NSSize(width: 580, height: 314))
            // The Large Battery widget.
            render(NookBatteryWidget(monitor: power, bluetooth: BluetoothMonitor(), compact: false, large: true)
                    .frame(width: 300, height: Design.nookHeight - 70).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("battery-widget-large.png"), size: NSSize(width: 300, height: Design.nookHeight - 70))
            // Small and Medium, side by side.
            render(HStack(spacing: 12) {
                NookBatteryWidget(monitor: power, bluetooth: BluetoothMonitor(), compact: true).frame(width: 116, height: 70)
                NookBatteryWidget(monitor: power, bluetooth: BluetoothMonitor(), compact: false).frame(width: 160, height: 170)
            }
            .padding(12).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("battery-widget-small-medium.png"), size: NSSize(width: 324, height: 194))
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
            // The Map, with a pin dropped on Tokyo.
            WidgetOptions.shared.clockPin = .init(latitude: 35.7, longitude: 139.7, zone: "Asia/Tokyo", name: "Tokyo")
            for (name, width) in [("map-medium", 320.0), ("map-large", 460.0)] {
                WidgetOptions.shared.clockStyle = .map
                render(NookClockWidget(compact: false).frame(width: width, height: 170)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(14).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                       to: directory.appendingPathComponent("clock-\(name).png"), size: NSSize(width: width + 28, height: 198))
            }
            // The Clock page: the Map, time scrubber and places at page size.
            WidgetOptions.shared.clockPlaces = ["America/New_York", "Europe/London", "Asia/Tokyo"]
            render(ClockPage().frame(width: 620, height: 300)
                    .background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("clock-page.png"), size: NSSize(width: 620, height: 300))
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
            for tab in CodingPanel.Tab.allCases where tab != .shell {
                render(CodingPanel(tab: tab).frame(width: 760, height: 330).padding(20).background(ThemeStore.shared.notch.surface).preferredColorScheme(.dark),
                       to: directory.appendingPathComponent("coding-\(tab.rawValue).png"), size: NSSize(width: 800, height: 370))
            }
            captureTerminalTabs(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "site-converter" {
            if ProcessInfo.processInfo.environment["MACSPACES_DEMO_THEME"] == "blossom" { ThemeStore.shared.selectFamily(.blossom) }
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
                    if ProcessInfo.processInfo.environment["MACSPACES_DEMO_THEME"] == "blossom" {
                        WebsiteBlossomWallpaper()
                    } else if let flat {
                        (flat == "white" ? Color.white : Color.black)
                    } else {
                        LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.24), Color(red: 0.36, green: 0.27, blue: 0.42)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    ConverterWheelView(wheel: wheel).environment(\.colorScheme, .dark).scaleEffect(1.75)
                    // The site's poster: the pointer on the lit wedge, as in the reel.
                    if ProcessInfo.processInfo.environment["MACSPACES_DEMO_THEME"] == "blossom", let hovered {
                        let step = 360 / Double(max(wheel.actions.count, 1))
                        let angle = (Double(hovered) * step - 90 + step * 0.18) * .pi / 180
                        let radius = ((ConverterWheel.innerRadius + ConverterWheel.outerRadius) / 2 + 24) * 1.75
                        Image(systemName: "cursorarrow").font(.system(size: 24)).foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 2)
                            .position(x: 600 + cos(angle) * radius + 7, y: 351 + sin(angle) * radius + 11)
                    }
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
            ThemeStore.shared.selectFamily(ProcessInfo.processInfo.environment["MACSPACES_DEMO_THEME"] == "blossom" ? .blossom : .everforest)
            NookThemePicker.startsFullyOpen = true
            let picker = NookThemePicker().padding(24).frame(width: 760)
                .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark)
            let height = NSHostingView(rootView: picker).fittingSize.height
            render(picker.frame(height: height), to: directory.appendingPathComponent("themes-all.png"), size: NSSize(width: 760, height: height))
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "site-green" {
            // Website stills in Everforest: the clipboard popup and the coding tabs,
            // all with synthetic data (no real clips or logs).
            ThemeStore.shared.selectFamily(ProcessInfo.processInfo.environment["MACSPACES_DEMO_THEME"] == "blossom" ? .blossom : .everforest)
            let surface = ThemeStore.shared.notch.surface
            let monitor = ClipboardMonitor()
            // Every clip fits its row whole (no "…").
            monitor.setPreviewEntries(["Spring workspace\nShare the launch kit", "https://example.com/launch-notes",
                                       "#F59AB5", "brew upgrade", "Meet at the north entrance", "Invoice 1042", "#24161C",
                                       "let total = items.reduce(0, +)", "Weekend plan", "Flight AB 123, seat 14C", "Table for four at 7"])
            if let first = monitor.entries.first { _ = monitor.toggleFavorite(first) }
            let model = ClipboardPopup.shared.model
            model.open(monitor: monitor)
            model.setCursor(0)
            render(ClipboardPopupView(model: model).frame(width: 660, height: 440).background(surface).preferredColorScheme(.dark),
                   to: directory.appendingPathComponent("clipboard-popup-green.png"), size: NSSize(width: 660, height: 440))
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
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "site-agent-popout" {
            captureAgentPopoutClip(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "homebrew" {
            captureHomebrew(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "agent-popout" {
            captureAgentPopout(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "notch-shapes" {
            captureNotchShapes(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "notch-looks" {
            captureNotchLooks(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "island-shapes" {
            captureIslandShapes(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "motion-cost" {
            measureMotionCost(to: directory)
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "settings-controls" {
            SettingsControlsCaptures.capture(to: directory)
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "themes-redesign" {
            ThemesRedesignCaptures.capture(to: directory)
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "theme-lag" {
            ThemeLagChecks.measure(to: directory)
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "theme-lag-legacy" {
            ThemeLagChecks.measure(to: directory, legacy: true)
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "bubble-exit" {
            BubbleExitCaptures.capture(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "open-morph-song" {
            OpenMorphCaptures.captureSong(into: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "open-morph" {
            OpenMorphCaptures.capture(to: directory)
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "pulse-compare" {
            PerformanceBudget.comparePulse(to: directory)
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "budget" {
            PerformanceBudget.measure(to: directory)
            return true
        }
        if ProcessInfo.processInfo.environment["MACSPACES_QA_SCOPE"] == "mood" {
            MoodLyricCaptures.capture(to: directory)
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
        for family in [ThemeFamily.macspaces, .everforest, .glass] {
            ThemeStore.shared.selectFamily(family)
            let view = HStack(spacing: 14) {
                tile("Clipboard") { ClipboardWidget(monitor: clipboard) }
                tile("System Stats") { SystemStatsWidget(service: stats) }
                tile("Keep Awake") { KeepAwakeWidget(service: awake) }
            }
            .padding(18)
            .background(ThemeStore.shared.notch.surfaceGradient)
            .environment(\.colorScheme, .dark)
            render(view, to: directory.appendingPathComponent("features-\(family.rawValue).png"))
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
            render(MediaPlayerView(nowPlaying: player).padding(.horizontal, 5).frame(width: 300, height: 190)
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
        ThemeStore.shared.selectFamily(.macspaces)
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
        // Karma (2.38) on the Music and Calendar pages.
        ThemeStore.shared.selectFamily(.karma)
        for tab in [NotchTab.music, .calendar] {
            let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
                settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
                timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
            model.selectedTab = tab; model.state = .expanded
            render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("karma-\(tab.rawValue).png"),
                   size: NSSize(width: model.expandedSize.width + 52, height: model.expandedSize.height + 28))
        }
        SettingsNavigationModel.shared.selection = .appearance
        render(SettingsView(), to: directory.appendingPathComponent("settings-appearance-karma.png"), size: NSSize(width: 980, height: 1180))
        // Every drawer open, to review all palettes.
        NookThemePicker.startsFullyOpen = true
        ThemeStore.shared.selectFamily(.blossom)
        render(SettingsView(), to: directory.appendingPathComponent("settings-themes.png"), size: NSSize(width: 980, height: 2150))
        NookThemePicker.startsFullyOpen = false
        // Patterned themes on a real page.
        for (family, tab) in [(ThemeFamily.blossom, NotchTab.music), (.monsoon, .calendar), (.alpine, .weather),
                              (.rainbow, .timers), (.synthwave, .music), (.codeRain, .system), (.lava, .reminders), (.firefly, .calendar)] {
            ThemeStore.shared.selectFamily(family)
            let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
                settings: dockSettings, shelf: basket, nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
                timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: lyrics)
            model.selectedTab = tab; model.state = .expanded
            render(NotchContainerView(viewModel: model), to: directory.appendingPathComponent("motif-\(family.rawValue).png"),
                   size: NSSize(width: model.expandedSize.width + 52, height: model.expandedSize.height + 28))
        }
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
        // Reduce Motion holds lyric motion still for these captures.
        let saved = (store.family, store.lyricStyle, store.reduceMotionPreference)
        store.reduceMotionPreference = true
        for family in [ThemeFamily.macspaces, .karma] {
            store.selectFamily(family)
            for style in LyricStyle.allCases {
                store.lyricStyle = style
                lyrics.setPreview(current: "We left the windows open", upcoming: "", source: .lyrics)
                render(MediaPlayerView(nowPlaying: player, largeArtwork: true, lyricsService: lyrics)
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
        store.selectFamily(.macspaces); store.lyricStyle = .poster
        for (index, line) in ["I don't get starstruck easily anymore these days",
                              "And when we were young we would run through the evening",
                              "Starstruck", "All we can do is"].enumerated() {
            lyrics.setPreview(current: line, upcoming: "", source: .lyrics)
            render(MediaPlayerView(nowPlaying: player, largeArtwork: true, lyricsService: lyrics)
                .frame(width: 572, height: 272)
                .background(store.notch.surface)
                .foregroundStyle(store.nookForeground)
                .environment(\.colorScheme, .dark),
                to: directory.appendingPathComponent("lyrics-poster-edge-\(index).png"), size: NSSize(width: 572, height: 272))
        }
        // Each Poster composition on the same lines.
        for (index, composition) in PosterLyric.Composition.allCases.enumerated() {
            let lines = ["I don't get starstruck easily anymore these days", "Need I go any further on",
                         "And when we were young we would run through the evening", "All we can do is"]
            render(VStack(spacing: 10) {
                    ForEach(lines, id: \.self) { line in
                        PosterLyric(line: line, accent: store.notch.accent, ink: store.nookForeground,
                                    size: CGSize(width: 340, height: 130), composition: composition)
                            .frame(width: 340, height: 130)
                    }
                }
                .padding(16).background(store.notch.surface).environment(\.colorScheme, .dark),
                to: directory.appendingPathComponent("poster-composition-\(index).png"), size: NSSize(width: 372, height: CGFloat(lines.count) * 140 + 22))
        }
        // Every scene theme's effect at Nook size, grouped as in Settings.
        for collection in ThemeCollection.allCases where collection != .terminal {
            for family in collection.families {
                store.selectFamily(family)
                guard let motif = family.motif else { continue }
                render(ThemeMotifView(motif: motif, accent: store.notch.accent, ink: store.nookForeground, softensCenter: true)
                        .frame(width: 640, height: 280)
                        .background(store.notch.surface),
                       to: directory.appendingPathComponent("scene-\(collection.rawValue)-\(family.rawValue).png"), size: NSSize(width: 640, height: 280))
            }
        }
        store.selectFamily(saved.0)
        store.lyricStyle = saved.1; store.reduceMotionPreference = saved.2
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
        for family in [ThemeFamily.macspaces, .gruvbox, .everforest] {
            ThemeStore.shared.selectFamily(family)
            player.setPreviewInfo(track)
            lyrics.setPreview(current: "A little light across the water", upcoming: "And a quiet place to land", source: .lyrics)
            renderMusicLayout(player, lyrics: lyrics, name: "music-layout-" + family.rawValue, directory: directory)
        }
        ThemeStore.shared.selectFamily(.macspaces)
        track.title = "A long track title that should wrap without moving the playback controls"
        player.setPreviewInfo(track)
        lyrics.setPreview(current: "A longer lyric that needs more than one line to remain comfortably readable",
                          upcoming: "The next line still fits below", source: .lyrics)
        renderMusicLayout(player, lyrics: lyrics, name: "music-layout-long", directory: directory)
        // Release details sit small beside the name; a song without lyrics centres its title.
        track.title = "There Is a Light That Never Goes Out - 2017 Master"
        track.album = "Hidden in Pieces: Live at the Royal Albert Hall"
        player.setPreviewInfo(track)
        lyrics.setPreview(current: "Take me out tonight", upcoming: "Where there's music and there's people", source: .lyrics)
        renderMusicLayout(player, lyrics: lyrics, name: "music-layout-details", directory: directory)
        track.title = "Wonderwall - Remastered"
        player.setPreviewInfo(track)
        lyrics.setPreview(current: "", upcoming: "", source: .lyrics)
        renderMusicLayout(player, lyrics: lyrics, name: "music-layout-no-lyrics", directory: directory)
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
        render(MediaPlayerView(nowPlaying: player, largeArtwork: true, lyricsService: lyrics)
            .frame(width: 532, height: 272)
            .background(ThemeStore.shared.notch.surface)
            .foregroundStyle(ThemeStore.shared.nookForeground)
            .environment(\.colorScheme, .dark),
            to: directory.appendingPathComponent(name + ".png"), size: NSSize(width: 532, height: 272))
    }

    private static func renderMusic(_ player: NowPlayingController, name: String, directory: URL) {
        let view = MediaPlayerView(nowPlaying: player, largeArtwork: true)
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
    /// A synthetic picture: wide like a screenshot (a window on a desktop) or square like a photo.
    private static func writeQAPicture(_ url: URL, wide: Bool, hue: CGFloat) {
        let size = wide ? NSSize(width: 1440, height: 900) : NSSize(width: 900, height: 900)
        let picture = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(hue: (0.55 + hue).truncatingRemainder(dividingBy: 1), saturation: 0.45, brightness: 0.85, alpha: 1),
                                NSColor(hue: (0.75 + hue).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.45, alpha: 1)])?.draw(in: rect, angle: -50)
            if wide {
                NSColor(white: 0.97, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 220, dy: 150), xRadius: 24, yRadius: 24).fill()
                NSColor(white: 0.85, alpha: 1).setFill()
                for row in 0..<6 { NSBezierPath(roundedRect: NSRect(x: 290, y: 600 - row * 70, width: 600 - row * 50, height: 26), xRadius: 8, yRadius: 8).fill() }
            } else {
                NSColor(white: 1, alpha: 0.85).setFill()
                NSBezierPath(ovalIn: NSRect(x: 300, y: 300, width: 300, height: 300)).fill()
            }
            return true
        }
        if let tiff = picture.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    private static func writeQAPDF(_ url: URL) {
        var box = CGRect(x: 0, y: 0, width: 420, height: 595)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        context.beginPDFPage(nil)
        context.setFillColor(NSColor(srgbRed: 0.18, green: 0.32, blue: 0.6, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 470, width: 420, height: 125))
        context.setFillColor(NSColor(white: 0.8, alpha: 1).cgColor)
        for row in 0..<8 { context.fill(CGRect(x: 40, y: 400 - row * 40, width: 340 - row * 20, height: 14)) }
        context.endPDFPage(); context.closePDF()
    }

    /// `cacheDisplay` draws every view into one bitmap, so SwiftTerm's `context.clear` of
    /// its dirty rect (it relies on its own layer's transparency) punched a transparent
    /// hole through whatever was drawn beneath, which viewers show as white. The window
    /// server composites each layer instead, so draw the terminals on their own and lay
    /// them over the rest, at the opacity they're shown with.
    private static func cacheDisplay(_ host: NSView, to bitmap: NSBitmapImageRep) {
        func terminals(in view: NSView) -> [TerminalView] {
            view.subviews.flatMap { ($0 as? TerminalView).map { [$0] } ?? terminals(in: $0) }
        }
        let shown = terminals(in: host).filter { !$0.isHidden }
        shown.forEach { $0.isHidden = true }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        shown.forEach { $0.isHidden = false }
        guard !shown.isEmpty, let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for terminal in shown where !terminal.isHiddenOrHasHiddenAncestor {
            var opacity: CGFloat = 1
            var view: NSView? = terminal
            while let current = view, current !== host.superview {
                opacity *= current.alphaValue * CGFloat(current.layer?.opacity ?? 1)
                view = current.superview
            }
            guard opacity > 0.01, let rep = terminal.bitmapImageRepForCachingDisplay(in: terminal.bounds) else { continue }
            terminal.cacheDisplay(in: terminal.bounds, to: rep)
            // Window coordinates: the host is the window's content view at its origin.
            rep.draw(in: terminal.convert(terminal.bounds, to: nil), from: .zero, operation: .sourceOver,
                     fraction: opacity, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The Terminal page on the theme's surface, following theme changes while it shows.
    private struct TerminalPageCapture: View {
        let shell: QuickShell
        @ObservedObject private var theme = ThemeStore.shared
        var body: some View {
            TerminalPage(shell: shell).frame(width: 740, height: 300).padding(.top, 10)
                .background(theme.notch.surface).foregroundStyle(theme.nookForeground)
                .environment(\.colorScheme, .dark)
        }
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
        let bitmap = qaBitmap(for: host)
        cacheDisplay(host, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }

    /// The view's bitmap at the screen's scale, or at `MACSPACES_RENDER_SCALE` (2 for the site's
    /// stills, also on a runner without a Retina screen).
    static func qaBitmap(for host: NSView) -> NSBitmapImageRep {
        guard let scale = Double(ProcessInfo.processInfo.environment["MACSPACES_RENDER_SCALE"] ?? ""), scale > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((host.bounds.width * scale).rounded()),
                                            pixelsHigh: Int((host.bounds.height * scale).rounded()), bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return host.bitmapImageRepForCachingDisplay(in: host.bounds)! }
        bitmap.size = host.bounds.size
        return bitmap
    }
}
#endif
