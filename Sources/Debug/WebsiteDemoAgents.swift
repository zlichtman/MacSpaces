#if DEBUG
import SwiftUI
import AppKit

/// The site's Agents video (`MACSPACES_DEMO_KIND=agents`, Feature QA's `agents` input): framed
/// close on the top of the tour's MacBook-sized stage (`crop(at:)`), the closed notch in the Clear look
/// playing a song (its cover and its sound as bubbles either side of the camera, nothing drawn
/// over the desktop); Claude Code needs you, so the agent bubble (a black circle with Claude's
/// app icon) slides out 2 pt beside the song's bubbles, its ring breathing; the pointer clicks it, the Nook opens on the Agents tab with that session outlined,
/// the pointer clicks Allow, and the Nook closes onto the song again, so it loops. The bubble
/// is drawn where its panel would be (the panel is hidden from captures), moving and breathing
/// as `AgentPopout` makes it; the agents' app icons come from `MACSPACES_DEMO_AGENT_ICONS`
/// (fetched at run time, never committed).
@MainActor
enum WebsiteDemoAgents {
    final class Clock: ObservableObject {
        @Published var t: Double = 0
        /// Where the Allow button is on the stage, once the Agents tab shows.
        @Published var allow: CGPoint?
    }

    static let stage = WebsiteDemoNotch.stage
    static let frameSize = WebsiteDemoNotch.frameSize
    /// Beats, in seconds of video.
    static let outAt = 0.5, clickAt = 3.2, allowAt = 5.2, closeAt = 6.45, length = 7.8
    /// The bubble fully out, at the top of its first breath.
    static let posterAt = outAt + 0.8
    /// Stills: the bubble out, the Agents tab with the session outlined, after Allow.
    static let stills: [(String, Double)] = [("agents-bubble", posterAt), ("agents-tab", 4.6), ("agents-allowed", 5.7)]
    /// Where the pointer rests at either end, on the desktop below and right of the notch,
    /// inside the close framing.
    static let rest = CGPoint(x: 905, y: 170)
    /// The framing: close on the notch (400 points of the stage's 1512, nearly 4x a full
    /// screen, centred on the row of bubbles: the cover left of the camera, its sound and the
    /// agent bubble right of it, so half a bubble right of the camera), so they read in the
    /// site's card; widening to the tour's framing as the Nook opens on the Agents tab, and back as it closes.
    static let tight: CGRect = {
        let side = AgentPopoutLayout.bubbleSide(forHeight: notchHeight)
        let centre = stage.width / 2 + AgentPopoutLayout.laneWidth(bubbles: 1, side: side) / 2
        return CGRect(x: centre - 200, y: 0, width: 400, height: 400 * frameSize.height / frameSize.width)
    }()
    static let notchHeight = WebsiteDemoProfile.notchSize.height
    static let wide = WebsiteDemoNotch.crop
    static let widenFor = 0.55

    static func crop(at t: Double) -> CGRect {
        func mix(_ p: Double) -> CGRect {
            let p = CGFloat(p)
            return CGRect(x: tight.minX + (wide.minX - tight.minX) * p, y: 0,
                          width: tight.width + (wide.width - tight.width) * p,
                          height: tight.height + (wide.height - tight.height) * p)
        }
        let opens = clickAt + 0.08
        if t < opens { return tight }
        if t < closeAt { return mix(ease(t, from: opens, to: opens + widenFor)) }
        return mix(1 - ease(t, from: closeAt, to: closeAt + widenFor))
    }
    /// Allow on the waiting card, measured from a capture, for when the accessibility tree
    /// doesn't have it (as on GitHub's runners).
    static let fallbackAllow = CGPoint(x: 552, y: 186)

    static func waiting(_ now: Date) -> AgentActivityMonitor.Session {
        var session = AgentActivityMonitor.Session(id: "b", agent: "claude", state: .needsYou,
                                                   folder: "/Users/sample/Projects/Garden", updated: now)
        session.appBundleID = "com.anthropic.claudefordesktop"; session.appName = "Claude"
        session.note = "Needs permission"; session.prompt = "Run the test suite and fix what fails"
        session.request = .init(hook: "1", tool: "Bash", title: "Run a command", detail: "npm test")
        session.started = now.addingTimeInterval(-65); session.steps = 6
        return session
    }

    /// The sessions at video time `t`. Their times count from `Date() - t`, so the request's
    /// countdown and the working times tick at the video's speed, not the slowed capture's.
    static func sessions(answered: Bool, at t: Double = 0) -> [AgentActivityMonitor.Session] {
        let now = Date().addingTimeInterval(-t)
        // The request arrives as the bubble comes out, so its 45 s countdown is fresh.
        var first = waiting(now.addingTimeInterval(outAt))
        if answered {
            var running = AgentActivityMonitor.Session(id: "b", agent: "claude", state: .working,
                                                       folder: first.folder, updated: now.addingTimeInterval(allowAt))
            running.appBundleID = first.appBundleID; running.appName = first.appName
            running.prompt = first.prompt; running.started = first.started; running.steps = 7
            running.action = "Running npm test"
            first = running
        }
        var editing = AgentActivityMonitor.Session(id: "a", agent: "claude", state: .working,
                                                   folder: "/Users/sample/Projects/Lighthouse", updated: now)
        editing.appBundleID = "com.apple.Terminal"; editing.appName = "Terminal"
        editing.action = "Editing StatusView.swift"; editing.prompt = "Make the status bar show every running job"
        editing.started = now.addingTimeInterval(-372); editing.steps = 23
        var codex = AgentActivityMonitor.Session(id: "c", agent: "codex", state: .working,
                                                 folder: "/Users/sample/Projects/Atlas", updated: now)
        codex.action = "Adding the page cursor"; codex.prompt = "Add pagination to the search API"
        codex.started = now.addingTimeInterval(-1260); codex.steps = 41
        return [first, editing, codex]
    }

    /// An App Store icon (full-bleed square) on the Mac's icon grid: an 824/1024 continuous
    /// squircle, as the apps' own Mac icons are drawn.
    static func macIcon(_ path: String) -> NSImage? {
        guard let art = NSImage(contentsOfFile: path) else { return nil }
        return NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
            let body = rect.insetBy(dx: rect.width * 100 / 1024, dy: rect.height * 100 / 1024)
            let shape = RoundedRectangle(cornerRadius: body.width * 0.225, style: .continuous).path(in: body).cgPath
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            context.addPath(shape); context.setFillColor(NSColor.black.cgColor); context.fillPath()
            context.restoreGState()
            context.addPath(shape); context.clip()
            art.draw(in: body)
            return true
        }
    }

    static func run(output: URL) {
        let env = ProcessInfo.processInfo.environment
        let frames = output.appendingPathComponent("agents-frames", isDirectory: true)
        try? FileManager.default.removeItem(at: frames)
        try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

        // The shared demo profile (WebsiteDemoProfile): the Clear look, the owner's Home, a running
        // timer and Keep Awake on, in the step's theme with its song.
        WebsiteDemoProfile.apply(theme: env["MACSPACES_DEMO_HERO_THEME"].flatMap(ThemeFamily.init(rawValue:)) ?? .nightBlossom,
                                 keepAwake: nil)
        defer { WebsiteDemoProfile.finish() }
        Design.demoClockDate = WebsiteDemoProfile.shownTime
        defer { Design.demoClockDate = nil }
        WebsiteDemoProfile.play(WebsiteDemoProfile.environmentTrack)

        // The agents' own icons, as on a Mac with Claude and ChatGPT installed.
        let icons = env["MACSPACES_DEMO_AGENT_ICONS"] ?? "/private/tmp/macspaces-agent-icons"
        for agent in ["claude", "codex"] {
            if let icon = macIcon("\(icons)/\(agent).png") { AgentActivityMonitor.previewAgentIcons[agent] = icon }
            else { print("Agents demo: no \(agent) icon in \(icons)") }
        }
        defer { AgentActivityMonitor.previewAgentIcons = [:] }
        let monitor = AgentActivityMonitor.shared
        monitor.preview(sessions(answered: false))
        monitor.spotlight = nil
        AgentPopout.shared.setPreview(monitor.sessions.filter { $0.state == .needsYou }, mood: .needsYou)
        UserDefaults.standard.set(CodingPanel.Tab.agents.rawValue, forKey: "terminal.tab")

        let model = WebsiteDemoProfile.model(availableWidth: stage.width)
        model.screenFrame = CGRect(origin: .zero, size: stage)

        // The theme's photo inside the Nook, as the tour draws it (`cacheDisplay` leaves out Core
        // Animation's layers and shaders, so the open Nook was plain).
        ThemeMotifView.flowersUseCoreAnimation = false
        ThemeMotifView.breezeUsesShader = false
        defer { ThemeMotifView.flowersUseCoreAnimation = true; ThemeMotifView.breezeUsesShader = true }

        let clock = Clock()
        let host = NSHostingView(rootView: AgentsStage(model: model, clock: clock).environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: stage)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.ignoresMouseEvents = true
        // On a screen, or SwiftUI's animations don't step and every frame is the end state.
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        window.setFrameOrigin(NSPoint(x: screen.minX, y: screen.maxY - stage.height))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let fps = WebsiteDemo234.fps
        func capture(_ crop: CGRect = wide) -> NSBitmapImageRep? { WebsiteDemoNotch.capture(host, crop: crop) }
        // Time slows so every frame is taken before the next is due (as the tour does), timed on
        // the busiest moment, the open Agents tab.
        model.expand(to: .terminal)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        _ = capture()
        var captures: [Double] = [], writes: [Double] = []
        for _ in 0..<5 {
            let began = Date()
            guard let bitmap = capture() else { continue }
            let captured = Date()
            _ = bitmap.representation(using: .png, properties: [:])
            captures.append(captured.timeIntervalSince(began)); writes.append(Date().timeIntervalSince(captured))
        }
        // The Allow button, from the accessibility tree (stage points, top-left origin).
        let measured = allowButton(in: host, window: window)
        print("Agents demo: Allow button \(measured.map { "at \(Int($0.x)), \(Int($0.y))" } ?? "not found; using the fallback")")
        model.collapse()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let captureCost = captures.sorted()[captures.count / 2], writeCost = writes.sorted()[writes.count / 2]
        let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        let scale = min(90, max(WebsiteDemo234.timeScale, ((captureCost + writeCost / cores) * fps * 2.5).rounded(.up)))
        print("Agents demo: a frame takes \(Int(captureCost * 1000)) ms to draw and \(Int(writeCost * 1000)) ms to write; time runs \(Int(scale))x slower")
        fflush(stdout)

        let writer = DispatchQueue(label: "agents-frame-writer", qos: .utility, attributes: .concurrent)
        let inFlight = DispatchSemaphore(value: 6)
        let group = DispatchGroup()
        Design.demoTimeScale = scale
        defer { Design.demoTimeScale = 1; window.orderOut(nil); window.contentView = nil }
        var done = Set<String>()
        func once(_ key: String, _ at: Double, _ t: Double, _ action: () -> Void) {
            if t >= at, done.insert(key).inserted { action() }
        }
        let start = Date()
        var lateness = 0.0, lateFrames = 0
        for n in 0..<Int(length * fps) {
            let t = Double(n) / fps
            clock.t = t
            // Clicking the bubble: the Agents tab on the waiting session, outlined (`openAgents`).
            once("open", clickAt + 0.08, t) {
                monitor.spotlight = "b"
                model.expand(to: .terminal)
            }
            once("measure", clickAt + 0.9, t) {
                clock.allow = allowButton(in: host, window: window) ?? measured ?? fallbackAllow
            }
            if t >= clickAt { monitor.preview(sessions(answered: t >= allowAt + 0.08, at: t)) }
            // Allow: the request is answered and the session goes back to work.
            once("allow", allowAt + 0.08, t) { AgentPopout.shared.setPreview([], mood: .needsYou) }
            once("close", closeAt, t) { model.collapse() }
            RunLoop.main.run(until: start.addingTimeInterval(t * scale))
            let late = Date().timeIntervalSince(start) / scale - t
            lateness = max(lateness, late)
            if late > 0.5 / fps { lateFrames += 1 }
            if n % 120 == 0 { print("Agents demo: frame \(n), \(String(format: "%.3f", late)) s late"); fflush(stdout) }
            guard let bitmap = capture(crop(at: t)) else { continue }
            var urls = [frames.appendingPathComponent(String(format: "f%05d.png", n))]
            if n == Int(posterAt * fps) { urls.append(output.appendingPathComponent("agents-poster.png")) }
            for (name, at) in stills where n == Int(at * fps) { urls.append(output.appendingPathComponent("\(name).png")) }
            inFlight.wait()
            group.enter()
            writer.async {
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    for url in urls { try? data.write(to: url) }
                }
                inFlight.signal(); group.leave()
            }
        }
        group.wait()
        monitor.spotlight = nil
        print("Agents demo: \(Int(length * fps)) frames in \(frames.path) at \(Int(scale))x slower; \(lateFrames) frames over half a frame late (at most \(String(format: "%.3f", lateness)) s)")
    }

    /// The first "Allow" button's centre on the stage, found through the accessibility tree.
    static func allowButton(in host: NSView, window: NSWindow) -> CGPoint? {
        func search(_ element: Any, _ depth: Int) -> NSRect? {
            guard depth < 60, let node = element as? NSAccessibilityProtocol else { return nil }
            let label = node.accessibilityLabel() ?? node.accessibilityTitle() ?? ""
            if label == "Allow", node.accessibilityRole() == .button { return node.accessibilityFrame() }
            for child in node.accessibilityChildren() ?? [] {
                if let found = search(child, depth + 1) { return found }
            }
            return nil
        }
        guard let frame = search(host, 0), !frame.isEmpty else { return nil }
        return CGPoint(x: frame.midX - window.frame.minX, y: window.frame.maxY - frame.midY)
    }

    /// cubic-bezier(x1, y1, x2, y2) at progress `x` (0…1), as Core Animation times it.
    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        func point(_ s: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
        }
        var low = 0.0, high = 1.0, s = x
        for _ in 0..<40 {
            s = (low + high) / 2
            if point(s, x1, x2) < x { low = s } else { high = s }
        }
        return point(s, y1, y2)
    }

    static func ease(_ t: Double, from: Double, to: Double) -> Double {
        bezier((t - from) / (to - from), 0.42, 0, 0.58, 1)
    }
}

/// The tour's desktop and menu bar, the Nook, the hardware notch, the agent bubble where its
/// panel would be, and the pointer.
private struct AgentsStage: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var clock: WebsiteDemoAgents.Clock
    @ObservedObject private var popout = AgentPopout.shared
    private typealias Demo = WebsiteDemoAgents

    var body: some View {
        let size = Demo.stage
        ZStack(alignment: .topLeading) {
            Group {
                if let asset = ProcessInfo.processInfo.environment["MACSPACES_DEMO_WALLPAPER_ASSET"] {
                    Image(asset).resizable().scaledToFill().overlay(Color.black.opacity(0.12))
                } else { WebsiteBlossomWallpaper() }
            }.frame(width: size.width, height: size.height).clipped()
            DemoMenuBar(height: model.geometry.height, within: Demo.wide.minX...Demo.wide.maxX, sparse: true)
                .frame(width: size.width)
            NotchContainerView(viewModel: model)
                .frame(width: size.width, height: size.height, alignment: .top)
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(.black).frame(width: model.geometry.width, height: model.geometry.height)
                .frame(width: size.width, alignment: .top)
            bubble
            pointer
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    /// Where the bubble's panel is and how opaque, at this moment: sliding out from under the
    /// notch's edge (0.38 s, `AgentPopout.show`), then tucking back quickly as the Nook opens.
    private var bubbleState: (frame: CGRect, alpha: Double)? {
        guard let notch = model.closedNotchFrame else { return nil }
        let screen = CGRect(origin: .zero, size: Demo.stage)
        let target = AgentPopoutLayout.frame(besideNotch: notch, on: screen)
        let tucked = AgentPopoutLayout.startFrame(besideNotch: notch)
        let t = clock.t
        func mix(_ p: Double) -> CGRect { target.offsetBy(dx: (tucked.minX - target.minX) * (1 - p), dy: 0) }
        if t < Demo.outAt { return nil }
        if t < Demo.clickAt + 0.08 {
            let linear = (t - Demo.outAt) / 0.38
            let p = Demo.bezier(linear, 0.2, 0.9, 0.25, 1.05)
            return (mix(linear >= 1 ? 1 : p), min(1, max(0, p)))
        }
        let hide = (t - Demo.clickAt - 0.08) / 0.12
        guard hide < 1 else { return nil }
        let p = 1 - Demo.bezier(hide, 0.42, 0, 0.58, 1)
        return (mix(p), p)
    }

    @ViewBuilder private var bubble: some View {
        if let state = bubbleState {
            AgentPopoutView(popout: popout, stillTime: max(0, clock.t - Demo.outAt))
                .frame(width: state.frame.width, height: state.frame.height)
                .opacity(state.alpha)
                .position(x: state.frame.midX, y: Demo.stage.height - state.frame.midY)
        }
    }

    /// The bubble's centre on the stage once it's out.
    private var bubblePoint: CGPoint {
        guard let notch = model.closedNotchFrame else { return Demo.rest }
        let target = AgentPopoutLayout.frame(besideNotch: notch, on: CGRect(origin: .zero, size: Demo.stage))
        return CGPoint(x: target.midX, y: Demo.stage.height - target.midY)
    }

    /// The pointer: resting on the desktop, to the bubble and a click, to Allow and a click,
    /// then back to rest as the Nook closes behind it.
    private var pointerState: (point: CGPoint, pressed: Bool) {
        let t = clock.t
        let allow = clock.allow ?? Demo.fallbackAllow
        let bubble = CGPoint(x: bubblePoint.x, y: bubblePoint.y + 3)
        func path(_ a: CGPoint, _ b: CGPoint, _ from: Double, _ to: Double) -> CGPoint {
            let p = Demo.ease(t, from: from, to: to)
            // A slight arc, as a hand moves a pointer.
            let lift = sin(p * .pi) * 18
            return CGPoint(x: a.x + (b.x - a.x) * p + lift * 0.4, y: a.y + (b.y - a.y) * p - lift)
        }
        let point: CGPoint
        if t < 2.0 { point = Demo.rest }
        else if t < 3.0 { point = path(Demo.rest, bubble, 2.0, 3.0) }
        else if t < 4.15 { point = bubble }
        else if t < 4.95 { point = path(bubble, allow, 4.15, 4.95) }
        else if t < 5.75 { point = allow }
        else { point = path(allow, Demo.rest, 5.75, 6.85) }
        let pressed = (Demo.clickAt..<Demo.clickAt + 0.14).contains(t) || (Demo.allowAt..<Demo.allowAt + 0.14).contains(t)
        return (point, pressed)
    }

    private var pointer: some View {
        let cursor = NSCursor.arrow
        let image = cursor.image
        let (point, pressed) = pointerState
        return Image(nsImage: image)
            .frame(width: image.size.width, height: image.size.height)
            .scaleEffect(pressed ? 0.86 : 1, anchor: UnitPoint(x: cursor.hotSpot.x / image.size.width, y: cursor.hotSpot.y / image.size.height))
            .offset(x: point.x - cursor.hotSpot.x, y: point.y - cursor.hotSpot.y)
    }
}
#endif
