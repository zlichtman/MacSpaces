#if DEBUG
import AppKit
import Combine
import SwiftUI

/// Main-thread run-loop passes, timed from waking to going back to sleep, with Core
/// Animation's commit (layout and drawing) included: a pass over a frame (16.7 ms) is a
/// dropped frame of any SwiftUI animation.
final class MainThreadPasses {
    private var observers: [CFRunLoopObserver] = []
    private var wokeAt: CFAbsoluteTime = 0
    private(set) var passes: [Double] = []
    /// When each pass began (`CFAbsoluteTimeGetCurrent`), alongside `passes`.
    private(set) var starts: [Double] = []

    func start() {
        passes = []
        starts = []
        // Waking is timed before anyone else's observer runs, sleeping after them all.
        let wake = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { [weak self] _, _ in
            self?.wokeAt = CFAbsoluteTimeGetCurrent()
        }
        let sleep = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { [weak self] _, _ in
            guard let self, self.wokeAt > 0 else { return }
            self.passes.append((CFAbsoluteTimeGetCurrent() - self.wokeAt) * 1000)
            self.starts.append(self.wokeAt)
            self.wokeAt = 0
        }
        for observer in [wake, sleep].compactMap({ $0 }) {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            observers.append(observer)
        }
    }

    func stop() -> [Double] {
        observers.forEach { CFRunLoopRemoveObserver(CFRunLoopGetMain(), $0, .commonModes) }
        observers = []
        return passes
    }
}

/// The `budget` scope: what the app costs where people feel it. CPU while the notch is
/// closed (idle, with a song, with the agent bubble) and while Music is open, and the
/// longest main-thread pass while hovering, opening, closing and switching pages, on
/// synthetic data in a window at the top of the screen. Writes `budget.txt`, and fails
/// (so CI fails) when a number goes over its limit. The limits are about twice what
/// GitHub's runners measured, so only a real regression trips them.
@MainActor enum PerformanceBudget {
    private static var report: [String] = []
    private static var overBudget: [String] = []

    enum Limit {
        /// CPU, % of one core: the closed notch, with or without a song or the agent bubble.
        static let closed = 1.5
        /// CPU with the Nook open on Home (in any scene) or on Music.
        static let open = 12.0
        /// The longest main-thread pass while hovering, opening or closing, in ms: the
        /// median of each set of repeats (shared runners have stalls of their own, from
        /// 12 to over 200 ms on the same build), against two frames.
        static let transition = 33.4
        /// A page's longest pass, the median over all pages, first visits and later ones,
        /// and for any one page a ceiling that only a real stall reaches.
        static let firstVisit = 50.0
        static let visit = 33.4
        static let anyVisit = 250.0
        /// Memory left behind by 30 opens, closes and page switches, in MB.
        static let growth = 10.0
        /// Publishes a second of anything a page watches, with nothing changing.
        static let idlePublishes = 0.2
    }

    private static func require(_ value: Double, under limit: Double, _ what: String) {
        guard value >= limit else { return }
        overBudget.append(String(format: "%@: %.2f, limit %.2f", what as NSString, value, limit))
    }

    private static func note(_ line: String) {
        print("budget " + line)
        report.append(line)
    }

    private static func run(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// CPU over `seconds` as a percentage of one core.
    private static func cpu(_ label: String, seconds: TimeInterval = 10, limit: Double) {
        let start = FeatureQAHarness.cpuSeconds()
        run(for: seconds)
        let percent = (FeatureQAHarness.cpuSeconds() - start) / seconds * 100
        note(String(format: "cpu %-34@ %5.2f%%", label as NSString, percent))
        require(percent, under: limit, "CPU " + label)
    }

    /// The longest main-thread pass, the passes over a frame and their total, while `action` plays out.
    @discardableResult
    private static func passes(_ label: String, settle: TimeInterval = 0.7, limit: Double, _ action: () -> Void) -> Double {
        let recorder = MainThreadPasses()
        recorder.start()
        action()
        run(for: settle)
        let passes = recorder.stop()
        let longest = passes.max() ?? 0
        let slow = passes.filter { $0 > 16.7 }
        note(String(format: "pass %-33@ longest %6.1f ms, %2d over a frame (%6.1f ms)",
                    label as NSString, longest, slow.count, slow.reduce(0, +)))
        require(longest, under: limit, "longest pass, " + label)
        return longest
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    /// Counts each object's publishes while `seconds` pass.
    private static func publishes(_ objects: [(String, ObservableObjectPublisher)], seconds: TimeInterval,
                                  during label: String, cpuLimit: Double) {
        var counts: [String: Int] = [:]
        let watches = objects.map { name, publisher in publisher.sink { counts[name, default: 0] += 1 } }
        cpu(label, seconds: seconds, limit: cpuLimit)
        watches.forEach { $0.cancel() }
        for (name, _) in objects {
            let rate = Double(counts[name] ?? 0) / seconds
            note(String(format: "publishes %-28@ %5.1f a second", "\(name), \(label)" as NSString, rate))
            require(rate, under: Limit.idlePublishes, "publishes of \(name), \(label)")
        }
    }

    static func measure(to directory: URL) {
        report = []
        // Line by line, so a failed run still shows every number.
        setvbuf(stdout, nil, _IOLBF, 0)
        // GitHub's runners have Reduce Motion on; measure what people with motion see.
        ThemeStore.shared.reduceMotionPreference = false; ThemeStore.shared.setPreviewSystemReduceMotion(false)
        ThemeStore.shared.selectFamily(.macspaces)
        let settings = NookSettings.shared
        settings.widgets = [.media, .clock, .timer, .weather]
        settings.expandOnHover = false
        let services = AppServices.shared
        services.shortcuts.setPreview(["Focus On", "Send to review"])
        services.weather.setPreviewSnapshot(.init(temperature: 20, weatherCode: 1, high: 22, low: 12))
        services.systemStats.setPreview()

        let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
            settings: settings, shelf: ShelfStore.shared, nowPlaying: services.nowPlaying, powerMonitor: services.powerMonitor,
            timerService: services.timerService, bluetoothMonitor: services.bluetooth,
            systemActivityMonitor: services.systemActivity, teleprompter: services.teleprompter)
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 1100, height: 520)
        let window = NSWindow(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height,
                                                  width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.level = .statusBar
        window.contentView = NSHostingView(rootView: NotchContainerView(viewModel: model))
        window.orderFrontRegardless()
        run(for: 2)

        // Closed: nothing a closed notch or an open page watches should publish while nothing changes.
        services.clipboard.start()
        run(for: 1)
        publishes([("clipboard", services.clipboard.objectWillChange), ("notch", model.objectWillChange),
                   ("system activity", services.systemActivity.objectWillChange)],
                  seconds: 10, during: "closed, idle", cpuLimit: Limit.closed)
        var track = NowPlayingInfo()
        track.title = "Harbour Lights - 2011 Remaster"; track.artist = "Sample Artist"; track.album = "Low Tide"
        track.sourceName = "Music"; track.capabilities = [.playPause, .previous, .next, .seek]
        track.duration = 236; track.elapsed = 81; track.isPlaying = true
        track.artwork = syntheticCover()
        services.nowPlaying.setPreviewInfo(track)
        services.teleprompter.setPreview(current: "Hold the evening light a little longer",
                                         upcoming: "Till the harbour lamps come on", source: .lyrics)
        run(for: 1)
        cpu("closed, song playing", limit: Limit.closed)

        // The agent bubble, breathing as it does on screen.
        AgentActivityMonitor.shared.preview()
        AgentPopout.shared.setPreview(AgentActivityMonitor.shared.sessions, shown: true)
        let bubble = NSWindow(contentRect: NSRect(x: screen.midX + 200, y: screen.maxY - 40, width: 32, height: 32),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        bubble.isOpaque = false; bubble.backgroundColor = .clear; bubble.level = .statusBar
        // Runners may have Reduce Motion on, which shows the still bubble; measure the breathing one.
        ThemeStore.shared.reduceMotionPreference = false; ThemeStore.shared.setPreviewSystemReduceMotion(false)
        bubble.contentView = NSHostingView(rootView: AgentPopoutView(popout: .shared))
        bubble.orderFrontRegardless()
        run(for: 1)
        // Cheap only counts if it still breathes: the ring must carry its layer animation.
        func layerTree(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(layerTree) }
        if !layerTree(bubble.contentView?.layer ?? CALayer()).contains(where: { $0.animation(forKey: "pulse") != nil }) {
            overBudget.append("The agent bubble's ring isn't breathing")
        }
        cpu("closed, song and agent bubble", limit: Limit.closed)
        bubble.orderOut(nil); bubble.contentView = nil
        AgentPopout.shared.setPreview([])

        // Hover peeks, then opening and closing.
        var hovers: [Double] = []
        for index in 0..<4 {
            hovers.append(passes("hover peek \(index + 1)", settle: 0.4, limit: Limit.anyVisit) { model.hoverChanged(true) })
            hovers.append(passes("hover leave \(index + 1)", settle: 0.4, limit: Limit.anyVisit) { model.hoverChanged(false) })
        }
        require(median(hovers), under: Limit.transition, "median longest pass, hovering")
        for page: NotchTab in [.nook, .music] {
            model.selectedTab = page
            var opens: [Double] = [], closes: [Double] = []
            for index in 0..<4 {
                opens.append(passes("open \(page.rawValue) \(index + 1)", limit: Limit.anyVisit) { model.expand() })
                closes.append(passes("close \(page.rawValue) \(index + 1)", limit: Limit.anyVisit) { model.collapse() })
            }
            // The first open builds the page (judged with the pages' first visits below).
            require(median(Array(opens.dropFirst())), under: Limit.transition, "median longest pass, opening on \(page.rawValue)")
            require(median(Array(closes.dropFirst())), under: Limit.transition, "median longest pass, closing from \(page.rawValue)")
        }

        // Every page, first visit then again.
        model.selectedTab = .nook
        model.expand()
        run(for: 1)
        let pages: [NotchTab] = [.music, .calendar, .notes, .weather, .clock, .timers, .clipboard, .shortcuts,
                                 .system, .terminal, .prompter, .reminders, .tray, .nook]
        for round in ["first", "again"] {
            var visits: [Double] = []
            for page in pages {
                visits.append(passes("page \(page.rawValue), \(round)", settle: 0.6, limit: Limit.anyVisit) {
                    withAnimation(Design.spring()) { model.selectedTab = page }
                })
            }
            require(median(visits), under: round == "first" ? Limit.firstVisit : Limit.visit, "median longest pass, pages, \(round)")
        }

        // Terminal on its GitHub tab (a year of contributions): the visit and the redraws after it.
        CodingStats.shared.preview()
        let savedTab = UserDefaults.standard.string(forKey: "terminal.tab")
        UserDefaults.standard.set(CodingPanel.Tab.github.rawValue, forKey: "terminal.tab")
        withAnimation(Design.spring()) { model.selectedTab = .nook }
        run(for: 1)
        let github = (0..<3).map { index in
            passes("page terminal on GitHub \(index + 1)", settle: 0.6, limit: Limit.anyVisit) {
                withAnimation(Design.spring()) { model.selectedTab = index % 2 == 0 ? .terminal : .nook }
            }
        }
        require(github[2], under: Limit.visit, "longest pass, Terminal's GitHub tab, again")
        UserDefaults.standard.set(savedTab, forKey: "terminal.tab")

        // Memory after many opens, closes and page switches: what stays behind.
        model.collapse()
        run(for: 1)
        let before = footprint()
        for index in 0..<30 {
            model.selectedTab = pages[index % pages.count]
            model.expand(); run(for: 0.35)
            model.collapse(); run(for: 0.35)
        }
        run(for: 2)
        let growth = footprint() - before
        note(String(format: "memory after 30 opens and closes   %+6.1f MB (%.0f MB in all)", growth, footprint()))
        require(growth, under: Limit.growth, "memory growth after 30 opens and closes (MB)")
        // Home open in scenes of each kind: none, flowers (Core Animation), a photo
        // with weather and a drawn tech effect (both on a timeline).
        model.selectedTab = .nook
        model.expand()
        run(for: 1)
        for family: ThemeFamily in [.macspaces, .blossom, .thunderstorm, .codeRain] {
            ThemeStore.shared.selectFamily(family)
            if let motif = family.motif { MotifImages.shared.prepare(motif) }
            model.collapse(); run(for: 2)
            model.expand(); run(for: 1)
            cpu("open, Home in \(family.rawValue)", limit: Limit.open)
        }
        ThemeStore.shared.selectFamily(.macspaces)

        // Music open, playing, with a count of what publishes.
        withAnimation(Design.spring()) { model.selectedTab = .music }
        run(for: 2)
        publishes([("now playing", services.nowPlaying.objectWillChange), ("lyrics", services.teleprompter.objectWillChange),
                   ("notch", model.objectWillChange), ("settings", settings.objectWillChange),
                   ("theme", ThemeStore.shared.objectWillChange), ("clipboard", services.clipboard.objectWillChange)],
                  seconds: 10, during: "open, Music playing", cpuLimit: Limit.open)
        model.collapse()
        run(for: 1)
        cpu("closed again, song playing", seconds: 5, limit: Limit.closed)
        services.clipboard.stop()

        window.orderOut(nil); window.contentView = nil
        if !overBudget.isEmpty { report.append("OVER BUDGET"); report += overBudget }
        try? report.joined(separator: "\n").write(to: directory.appendingPathComponent("budget.txt"), atomically: true, encoding: .utf8)
        // Over budget fails the run, so CI (and so a release) stops on a regression.
        guard overBudget.isEmpty else { fatalError("Over the performance budget:\n" + overBudget.joined(separator: "\n")) }
        print("Performance budget passed")
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    /// The `pulse-compare` scope: the agent bubble's ring as SwiftUI drew it (a 24 fps
    /// timeline over `AgentPopoutLayout.pulse`) against the Core Animation ring, pinned at
    /// eight moments of one 1.6 s breath. For each it reports the ring's width and
    /// opacity against the formula, and writes `pulse/old-N.png`, `pulse/new-N.png`, a
    /// side-by-side `pulse/compare.png` (old top, new below, 8x) and the pixel difference.
    static func comparePulse(to directory: URL) {
        let folder = directory.appendingPathComponent("pulse")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        ThemeStore.shared.selectFamily(.macspaces)
        AgentActivityMonitor.shared.preview()
        AgentPopout.shared.setPreview(AgentActivityMonitor.shared.sessions.filter { $0.id == "b" }, shown: true)
        let side: CGFloat = 32, scale: CGFloat = 8
        func host<V: View>(_ view: V) -> (NSWindow, NSView) {
            let hosting = NSHostingView(rootView: view.frame(width: side, height: side))
            hosting.frame = NSRect(x: 0, y: 0, width: side, height: side)
            let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: side, height: side), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            window.contentView = hosting
            window.orderFrontRegardless()
            run(for: 0.5)
            return (window, hosting)
        }
        func bitmap(_ draw: (CGContext) -> Void) -> CGImage {
            let pixels = Int(side * scale)
            let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.scaleBy(x: scale, y: scale)
            draw(context)
            return context.makeImage()!
        }
        func write(_ image: CGImage, _ name: String) {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
        }
        func layers(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(layers) }
        func render(_ view: NSView) -> CGImage {
            bitmap { context in
                // The presentation tree: what's on screen, animations included.
                (view.layer?.presentation() ?? view.layer)?.render(in: context)
            }
        }

        ThemeStore.shared.reduceMotionPreference = false; ThemeStore.shared.setPreviewSystemReduceMotion(false)
        print("pulse system Reduce Motion: \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion), shown: \(AgentPopout.shared.isShown)")
        let (liveWindow, live) = host(AgentPopoutView(popout: .shared))
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        let ringView = views(live).first { String(describing: type(of: $0)).contains("AgentPulseRingView") }
        print("pulse views: " + views(live).map { String(describing: type(of: $0)) }.joined(separator: ", "))
        guard let ringView, let ringLayer = ringView.layer,
              let ring = layers(ringLayer).compactMap({ $0 as? CAShapeLayer }).first(where: { $0.animation(forKey: "pulse") != nil }),
              let begin = ring.animation(forKey: "pulse")?.beginTime else {
            fatalError("The agent bubble's ring has no Core Animation pulse (ring view: \(ringView.map { "\($0.frame)" } ?? "none"))")
        }
        /// The live ring, stopped `t` into its breath.
        func pin(_ t: Double) -> CAShapeLayer {
            ring.speed = 0
            ring.timeOffset = begin + t
            CATransaction.flush()
            run(for: 0.05)
            return ring.presentation() ?? ring
        }
        // Neither breath has a fixed start on screen, so the old one is lined up with the
        // new by phase (found over 32 samples) before their shapes are compared.
        let samples = (0..<32).map { index -> (Double, Double) in
            let t = 1.6 * Double(index) / 32
            return (t, Double(pin(t).lineWidth))
        }
        func error(_ shift: Double) -> Double {
            var worst = 0.0
            for (t, width) in samples {
                let expected: Double = 1.5 + 1.2 * AgentPopoutLayout.pulse(at: t + shift)
                worst = max(worst, abs(width - expected))
            }
            return worst
        }
        let shifts: [Double] = stride(from: -0.4, through: 0.4, by: 0.005).map { $0 }
        let phase: Double = shifts.min { error($0) < error($1) } ?? 0
        var lines = [String(format: "phase: the Core Animation breath runs %.3f s behind the timeline's", -phase)]
        var difference = 0.0, worstWidth = 0.0, worstOpacity = 0.0
        var olds: [CGImage] = [], news: [CGImage] = []
        for index in 0..<8 {
            let t = 1.6 * Double(index) / 8
            let pulse = AgentPopoutLayout.pulse(at: t + phase)
            let presented = pin(t)
            let width = Double(presented.lineWidth), opacity = Double(presented.opacity)
            worstWidth = max(worstWidth, abs(width - (1.5 + 1.2 * pulse)))
            worstOpacity = max(worstOpacity, abs(opacity - (0.45 + 0.55 * pulse)))
            lines.append(String(format: "t %.1f s: pulse %.3f, ring %.2f pt at %.0f%% (SwiftUI %.2f pt at %.0f%%)",
                                t, pulse, width, opacity * 100, 1.5 + 1.2 * pulse, (0.45 + 0.55 * pulse) * 100))
            let new = render(live)
            let (oldWindow, old) = host(AgentPopoutView(popout: .shared, stillPulse: pulse))
            let before = render(old)
            oldWindow.orderOut(nil)
            write(before, "old-\(index).png"); write(new, "new-\(index).png")
            olds.append(before); news.append(new)
            difference = max(difference, meanDifference(before, new))
        }
        liveWindow.orderOut(nil)
        let tile = Int(side * scale)
        let strip = CGContext(data: nil, width: tile * 8, height: tile * 2, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        strip.setFillColor(CGColor(gray: 0.85, alpha: 1)); strip.fill(CGRect(x: 0, y: 0, width: tile * 8, height: tile * 2))
        for index in 0..<8 {
            strip.draw(olds[index], in: CGRect(x: index * tile, y: tile, width: tile, height: tile))
            strip.draw(news[index], in: CGRect(x: index * tile, y: 0, width: tile, height: tile))
        }
        write(strip.makeImage()!, "compare.png")
        lines.append(String(format: "worst ring width difference %.3f pt, opacity %.1f points, mean pixel difference %.2f%%",
                            worstWidth, worstOpacity * 100, difference * 100))
        lines.forEach { print("pulse " + $0) }
        try? lines.joined(separator: "\n").write(to: folder.appendingPathComponent("pulse.txt"), atomically: true, encoding: .utf8)
        // The same breath: within a tenth of a point and 3% opacity at every moment.
        precondition(worstWidth < 0.1 && worstOpacity < 0.03, "The Core Animation pulse drifts from the SwiftUI one")
        AgentPopout.shared.setPreview([])
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    /// The mean per-channel difference of two same-sized images, 0…1.
    private static func meanDifference(_ a: CGImage, _ b: CGImage) -> Double {
        func bytes(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return data
        }
        let left = bytes(a), right = bytes(b)
        let total = zip(left, right).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(left.count) / 255
    }

    /// The process's memory footprint, as Activity Monitor shows it, in MB.
    private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    private static func syntheticCover() -> NSImage {
        let side = 600
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 0.9, green: 0.4, blue: 0.3, alpha: 1), CGColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: side, height: side))
    }
}
#endif
