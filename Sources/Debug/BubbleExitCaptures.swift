#if DEBUG
import AppKit
import SwiftUI

/// The `bubble-exit` scope: the closed notch's activities arriving and leaving, the song
/// starting and stopping, with Reduce Motion forced off (the runners have it on) and once
/// with it on. Time runs 3x slower and frames are taken at 30 a second, so each frame is
/// 1/90 s, at 2x pixels. Per case and scenario: `bubble-exit/<case>-<scenario>/f000.png`
/// and two strips, `<case>-<scenario>-start.png` and `-stop.png` (every second frame,
/// top to bottom, cropped to the notch). Cases: the clear look on a notch, an island and a
/// notchless screen, the solid look on a notch and an island. Scenarios: the song alone;
/// the song beside a running timer, with the agent bubble. Plus stills of the clear look
/// at rest (`stills/<case>-<state>.png`): the song alone, the song and a timer, the song
/// and the agent bubble.
@MainActor enum BubbleExitCaptures {
    private static let slow = 3.0
    private static let size = NSSize(width: 560, height: 64)
    /// The middle of the stage, where the notch and its activities are.
    private static let crop = CGRect(x: 80, y: 0, width: 400, height: 64)

    static func capture(to directory: URL) {
        let folder = directory.appendingPathComponent("bubble-exit")
        let stills = folder.appendingPathComponent("stills")
        try? FileManager.default.createDirectory(at: stills, withIntermediateDirectories: true)
        let theme = ThemeStore.shared
        theme.selectFamily(.macspaces)
        theme.reduceMotionPreference = false
        theme.setPreviewSystemReduceMotion(false)
        let settings = NookSettings.shared
        settings.widgets = [.media, .clock, .timer]
        settings.expandOnHover = false
        settings.showMusicLiveActivity = true
        settings.showTimerLiveActivity = true
        AgentActivityMonitor.shared.preview()
        AgentPopout.shared.setPreview(AgentActivityMonitor.shared.sessions.filter { $0.id == "b" })
        defer { Design.demoTimeScale = 1 }

        let menuBar: CGFloat = 32
        let notch = NotchGeometry.Reading(screenWidth: 1512, safeTop: 32, auxiliaryLeft: 663.5, auxiliaryRight: 663.5)
        let island = NotchGeometry.Reading(screenWidth: 1512, safeTop: 0, menuBarHeight: menuBar, hasCameraIsland: true,
                                           islandCutout: CGRect(x: 0, y: 5, width: 120, height: 24))
        let notchless = NotchGeometry.Reading(screenWidth: 1512, safeTop: 0, menuBarHeight: menuBar)
        let cases: [(String, NotchGeometry.Reading, NotchGeometry.Look, Bool)] = [
            ("notch-clear", notch, .clear, false),
            ("island-clear", island, .clear, false),
            ("notchless-clear", notchless, .clear, false),
            ("notch-solid", notch, .solid, false),
            ("island-solid", island, .solid, false),
            ("notch-clear-reducemotion", notch, .clear, true),
        ]
        for (name, reading, look, reduce) in cases {
            theme.reduceMotionPreference = reduce
            let geometry = NotchGeometry.resolve(reading, look: look, notchlessHint: true)
            for (scenario, timer, agent) in [("song", false, false), ("song-timer-agent", true, true)] {
                let model = makeModel(geometry)
                play(false)
                AppServices.shared.timerService.setPreview(remaining: timer ? 754 : 0, total: 1500)
                let stage = Stage(model: model, agent: agent, menuBar: menuBar)
                let frames = folder.appendingPathComponent("\(name)-\(scenario)")
                let images = record(stage, model: model, to: frames)
                for (part, range) in [("start", 0..<45), ("stop", 45..<90)] {
                    let picks = Array(range).filter { $0 % 2 == 0 && $0 < images.count }
                    write(strip(picks.map { images[$0] }), to: folder.appendingPathComponent("\(name)-\(scenario)-\(part).png"))
                }
            }
            // Stills of the clear look at rest.
            guard look == .clear, !reduce else { continue }
            for (state, timer, agent) in [("song", false, false), ("song-timer", true, false), ("song-agent", false, true)] {
                let model = makeModel(geometry)
                play(true)
                AppServices.shared.timerService.setPreview(remaining: timer ? 754 : 0, total: 1500)
                let image = still(Stage(model: model, agent: agent, menuBar: menuBar), model: model)
                if let image { write(image, to: stills.appendingPathComponent("\(name)-\(state).png")) }
            }
        }
        play(false)
        AppServices.shared.timerService.setPreview(remaining: 0, total: 1500)
        theme.reduceMotionPreference = false
        captureAgentStates(to: stills)
        AgentPopout.shared.setPreview(AgentActivityMonitor.shared.sessions.filter { $0.id == "b" })
        print("Bubble exit captures written")
    }

    /// The agent bubble in each state, beside the clear look's song: needs you (Claude),
    /// two need you (the count), working (Codex), and done (the tick on the finished
    /// session's icon). `stills/agent-<state>.png`. The runners have neither Claude's nor
    /// ChatGPT's app, so each shows the app its session runs in, else Terminal's.
    private static func captureAgentStates(to stills: URL) {
        let monitor = AgentActivityMonitor.shared
        monitor.preview()
        let sessions = monitor.sessions
        var second = AgentActivityMonitor.Session(id: "a2", agent: "claude", state: .needsYou,
                                                 folder: "/Users/sample/Projects/Lighthouse", updated: Date())
        second.appBundleID = "com.apple.Terminal"; second.appName = "Terminal"
        let states: [(String, [AgentActivityMonitor.Session], AgentFace.Mood, AgentActivityMonitor.Session?)] = [
            ("needs-you", sessions.filter { $0.id == "b" }, .needsYou, nil),
            ("needs-you-two", sessions.filter { $0.id == "b" } + [second], .needsYou, nil),
            ("working", sessions.filter { $0.id == "c" }, .working, nil),
            ("done", [], .cheering, sessions.first { $0.id == "d" }),
            ("done-unknown-app", [], .cheering, AgentActivityMonitor.Session(id: "e", agent: "claude", state: .done,
                                                                         folder: "/Users/sample/Projects/Garden", updated: Date())),
        ]
        let geometry = NotchGeometry.resolve(.init(screenWidth: 1512, safeTop: 32, auxiliaryLeft: 663.5, auxiliaryRight: 663.5),
                                             look: .clear, notchlessHint: true)
        play(true)
        for (name, list, mood, finished) in states {
            AgentPopout.shared.setPreview(list, mood: mood)
            AgentPopout.shared.setPreviewFinished(finished)
            if let image = still(Stage(model: makeModel(geometry), agent: true, menuBar: 32), model: makeModel(geometry)) {
                write(image, to: stills.appendingPathComponent("agent-\(name).png"))
            }
        }
        AgentPopout.shared.setPreviewFinished(nil)
        play(false)
    }

    private static func makeModel(_ geometry: NotchGeometry) -> NotchViewModel {
        let model = NotchViewModel(geometry: geometry, availableWidth: 1512, settings: NookSettings.shared, shelf: ShelfStore.shared,
                                   nowPlaying: AppServices.shared.nowPlaying, powerMonitor: AppServices.shared.powerMonitor,
                                   timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                                   systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: AppServices.shared.teleprompter)
        model.screenFrame = CGRect(origin: .zero, size: size)
        return model
    }

    private static let cover = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
        NSGradient(colors: [NSColor(red: 0.98, green: 0.55, blue: 0.35, alpha: 1),
                            NSColor(red: 0.42, green: 0.25, blue: 0.62, alpha: 1)])?.draw(in: rect, angle: -60)
        NSColor(white: 1, alpha: 0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: 70, y: 66, width: 30, height: 30)).fill()
        return true
    }

    private static func play(_ playing: Bool) {
        var track = NowPlayingInfo()
        track.title = "Golden Hour"; track.artist = "Sample Artist"; track.sourceName = "Music"
        track.isPlaying = playing; track.duration = 240; track.elapsed = 150; track.artwork = cover
        AppServices.shared.nowPlaying.setPreviewInfo(track)
    }

    /// The top of a light desktop: the menu bar, the Nook, the hardware drawn over it
    /// (black whatever is under it), and the agent bubble where its panel would be,
    /// moving as `AgentPopout` moves its panel.
    private struct Stage: View {
        @ObservedObject var model: NotchViewModel
        let agent: Bool
        let menuBar: CGFloat
        @State private var agentFrame: CGRect?

        private var screen: CGRect { CGRect(origin: .zero, size: BubbleExitCaptures.size) }
        private var target: CGRect { AgentPopoutLayout.frame(besideNotch: model.closedNotchFrame ?? .zero, on: screen) }

        var body: some View {
            let geometry = model.geometry
            let frame = agentFrame ?? target
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.78, green: 0.84, blue: 0.93), Color(red: 0.93, green: 0.86, blue: 0.80)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color.white.opacity(0.35)).frame(height: menuBar)
                NotchContainerView(viewModel: model)
                switch geometry.cutout {
                case .notch:
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(Color.black)
                        .frame(width: geometry.width, height: geometry.height)
                case .island:
                    Capsule().fill(Color.black).frame(width: 120, height: 24).offset(y: 5)
                case .none:
                    EmptyView()
                }
                if agent {
                    AgentPopoutView(popout: AgentPopout.shared, stillPulse: 0.6)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: screen.maxY - frame.midY)
                }
            }
            .frame(width: screen.width, height: screen.height)
            .onChange(of: model.collapsedActivityKinds) { _ in
                // As on screen, the panel is told a run-loop turn later.
                DispatchQueue.main.async {
                    let next = target
                    AgentPopout.previewMove(from: frame, to: next) { agentFrame = next }
                }
            }
        }
    }

    /// Starts the song at frame 3 and stops it at frame 48, writing every frame.
    private static func record<V: View>(_ view: V, model: NotchViewModel, to frames: URL) -> [CGImage] {
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let (window, host) = host(view)
        Design.demoTimeScale = slow
        var images: [CGImage] = []
        let start = Date()
        for n in 0..<90 {
            if n == 3 { play(true) }
            if n == 48 { play(false) }
            RunLoop.main.run(until: start.addingTimeInterval(Double(n) / 30))
            guard let image = snapshot(host) else { continue }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: frames.appendingPathComponent(String(format: "f%03d.png", n)))
            images.append(image)
        }
        Design.demoTimeScale = 1
        window.close()
        return images
    }

    private static func still<V: View>(_ view: V, model: NotchViewModel) -> CGImage? {
        let (window, host) = host(view)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        defer { window.close() }
        return snapshot(host)
    }

    private static func host<V: View>(_ view: V) -> (NSWindow, NSHostingView<V>) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.ignoresMouseEvents = true
        // On screen: off it, the display link that steps SwiftUI's animations doesn't run.
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window.setFrameOrigin(NSPoint(x: screen.minX, y: screen.maxY - size.height))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        return (window, host)
    }

    private static func snapshot(_ host: NSView) -> CGImage? {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap.cgImage
    }

    /// Frames top to bottom, each cropped to the notch, with a thin gap between them.
    private static func strip(_ images: [CGImage]) -> CGImage {
        let cropped = images.compactMap { $0.cropping(to: CGRect(x: crop.minX * 2, y: crop.minY * 2,
                                                                 width: crop.width * 2, height: crop.height * 2)) }
        let width = Int(crop.width * 2), height = Int(crop.height * 2), gap = 4
        let context = CGContext(data: nil, width: width, height: max(1, cropped.count * (height + gap)),
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        for (row, image) in cropped.enumerated() {
            context.draw(image, in: CGRect(x: 0, y: (cropped.count - 1 - row) * (height + gap), width: width, height: height))
        }
        return context.makeImage()!
    }

    private static func write(_ image: CGImage, to url: URL) {
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
