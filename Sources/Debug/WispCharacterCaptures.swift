#if DEBUG
import SwiftUI
import AppKit

/// Wisp's eyes for review, part of the `wisp` scope, in `wisp-character/`:
/// - `sheet-<theme>.png` (Noir, Frost, Glass, Clear, Everforest; Glass and Clear over a
///   synthetic desktop as the Nook shows them): every mood at the page's size (80 pt), with the
///   pointer on it, mid-blink, glancing, the speaking mouth open and closed, each prop, the 48 pt
///   size and the dock glyph, at 2x.
/// - `stills-<theme>.png`: every mood as Reduce Motion shows it, at 48 pt.
/// - `transitions-<theme>.png` (Noir, Glass): the in-between poses of a blink, a glance, the
///   mood changes and the speaking mouth, each as five steps of the pose's mix.
/// - `motion-cost.txt`: CPU with the 80 pt face live on screen: idle (blinks and glances),
///   the pointer moving (gaze updates at the page's ten a second), speaking, and still.
@MainActor
enum WispCharacterCaptures {
    static let scale: CGFloat = 2

    /// `measuring` adds `motion-cost.txt` (the `wisp` scope; `wisp-looks` skips it).
    static func capture(to directory: URL, measuring: Bool = true) {
        let root = directory.appendingPathComponent("wisp-character")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let theme = ThemeStore.shared
        let saved = (theme.family, theme.reduceMotionPreference)
        // Runners have the system's Reduce Motion on; these show the motion people see.
        theme.reduceMotionPreference = false
        theme.setPreviewSystemReduceMotion(false)
        let families: [(String, ThemeFamily)] = [("noir", .macspaces), ("frost", .frost), ("glass", .glass), ("clear", .clear),
                                                 ("everforest", .everforest)]
        for (name, family) in families {
            theme.selectFamily(family)
            sheet(to: root.appendingPathComponent("sheet-\(name).png"))
            write(StillRow().padding(12).background(Backdrop()).foregroundStyle(theme.nookForeground),
                  size: NSSize(width: 10 * 110 + 24, height: 128), to: root.appendingPathComponent("stills-\(name).png"))
            if name == "noir" || name == "glass" {
                transitions(to: root.appendingPathComponent("transitions-\(name).png"))
            }
        }
        theme.selectFamily(.macspaces)
        if measuring { measureCost(to: root) }
        theme.selectFamily(saved.0)
        theme.reduceMotionPreference = saved.1
        theme.setPreviewSystemReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        print("Wisp character captures written")
    }

    /// The Nook's surface, over a synthetic desktop in a Glass or Clear theme so the face's glass shows.
    private struct Backdrop: View {
        @ObservedObject private var theme = ThemeStore.shared
        var body: some View {
            if let tint = theme.family.glassTint {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.16, green: 0.36, blue: 0.7), Color(red: 0.86, green: 0.46, blue: 0.3),
                                            Color(red: 0.95, green: 0.82, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    theme.notch.surface.opacity(max(0.12, tint))
                }
            } else {
                theme.notch.surface
            }
        }
    }

    // MARK: Sheet

    private struct Cell: View {
        let label: String
        let face: AnyView
        var body: some View {
            VStack(spacing: 2) {
                face
                Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
            .frame(width: 190, height: 170)
        }
    }

    private static func sheet(to url: URL) {
        let theme = ThemeStore.shared
        typealias Item = (String, WispMood, WispFace.Preview, Int)
        let still = WispFace.Preview()
        let moods: [Item] = [
            ("idle", .idle, still, 0), ("pointer near", .idle, still, 1), ("pointer on it", .idle, still, 2),
            ("blink", .idle, WispFace.Preview(blink: 0.6), 0), ("glance", .idle, WispFace.Preview(glance: CGPoint(x: -0.85, y: 0.3)), 0),
            ("listening", .listening, still, 0), ("thinking", .thinking, still, 0),
            ("speaking, open", .speaking, still, 0), ("speaking, closed", .speaking, WispFace.Preview(mouthOpen: false), 0),
            ("happy", .happy, still, 0), ("celebrating", .celebrating, still, 0),
            ("surprised", .surprised, still, 0), ("sleepy", .sleepy, still, 0),
            ("confused", .confused, still, 0), ("love", .love, still, 0),
        ]
        let props: [(String, WispProp, WispMood)] = [
            ("tea timer", .mug, .happy), ("timer", .stopwatch, .idle), ("reminder", .bell, .happy),
            ("focus", .shades, .idle), ("note", .note, .idle),
        ]
        let columns = 7
        func row(_ cells: [Cell]) -> some View {
            HStack(spacing: 0) { ForEach(cells.indices, id: \.self) { cells[$0] } }
        }
        let moodCells = moods.map { item in
            Cell(label: item.0, face: AnyView(WispFace(mood: item.1, size: 80, gaze: item.3 > 0 ? CGPoint(x: 0.25, y: 0.25) : nil,
                                                       near: item.3 > 0, curious: item.3 == 2, preview: item.2)))
        }
        let propCells = props.map { item in
            Cell(label: item.0, face: AnyView(WispFace(mood: item.2, size: 80, preview: WispFace.Preview(prop: item.1))))
        } + [
            Cell(label: "48 pt", face: AnyView(WispFace(mood: .idle, size: 48, preview: still).frame(width: 116, height: 92))),
            Cell(label: "dock glyph 14, 28 pt", face: AnyView(HStack(spacing: 14) { WispGlyph(size: 14); WispGlyph(size: 28) }
                .foregroundStyle(theme.nookForeground).frame(width: 116, height: 92))),
        ]
        let width = CGFloat(columns) * 190 + 32
        let content = VStack(alignment: .leading, spacing: 12) {
            Text("Wisp, \(theme.family.rawValue): moods at 80 pt").font(.headline)
            row(Array(moodCells.prefix(columns)))
            row(Array(moodCells[columns..<min(moodCells.count, 2 * columns)]))
            row(Array(moodCells.suffix(moodCells.count - 2 * columns)))
            Text("Props, 48 pt and the dock glyph").font(.headline)
            row(propCells)
        }
        .padding(16)
        .frame(width: width, alignment: .leading)
        .background(Backdrop())
        .foregroundStyle(theme.nookForeground)
        write(content, size: NSSize(width: width, height: 4 * 170 + 110), to: url)
    }

    /// Every mood as Reduce Motion shows it, at 48 pt.
    private struct StillRow: View {
        @ObservedObject private var theme = ThemeStore.shared
        var body: some View {
            HStack(spacing: 6) {
                ForEach([WispMood.idle, .listening, .thinking, .speaking, .happy, .surprised, .sleepy, .confused, .love, .celebrating],
                        id: \.self) { mood in
                    VStack(spacing: 2) {
                        WispFace(mood: mood, size: 48, preview: WispFace.Preview())
                        Text(String(describing: mood)).font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .frame(width: 104, height: 100)
                }
            }
        }
    }

    // MARK: Transitions

    private static func transitions(to url: URL) {
        let theme = ThemeStore.shared
        let style = WispFaceStyle.current(theme)
        let idle = WispPose(mood: .idle)
        let rows: [(String, WispPose, WispPose)] = [
            ("blink", idle, WispPose(mood: .idle, blink: 1)),
            ("glance", idle, WispPose(mood: .idle, gaze: CGPoint(x: 0.85, y: -0.4))),
            ("pointer arriving", idle, WispPose(mood: .idle, near: true, curious: true, gaze: CGPoint(x: -0.25, y: 0.25))),
            ("poke", WispPose(mood: .idle, curious: true), WispPose(mood: .surprised)),
            ("idle to celebrating", idle, WispPose(mood: .celebrating)),
            ("idle to confused", idle, WispPose(mood: .confused)),
            ("idle to thinking", idle, WispPose(mood: .thinking)),
            ("idle to happy", idle, WispPose(mood: .happy)),
            ("idle to surprised", idle, WispPose(mood: .surprised)),
            ("idle to love", idle, WispPose(mood: .love)),
            ("idle to sleepy", idle, WispPose(mood: .sleepy)),
            ("thinking to speaking", WispPose(mood: .thinking), WispPose(mood: .speaking)),
            ("speaking, closing", WispPose(mood: .speaking), WispPose(mood: .speaking, mouthOpen: false)),
            ("focus shades", idle, WispPose(mood: .idle, prop: .shades)),
        ]
        let steps: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
        let content = VStack(alignment: .leading, spacing: 4) {
            Text("Wisp, \(theme.family.rawValue): transitions, five steps each").font(.headline)
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    Text(rows[index].0).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .leading)
                    ForEach(steps, id: \.self) { step in
                        WispFaceArt(pose: rows[index].1.mixed(with: rows[index].2, step), size: 64, style: style)
                            .frame(width: 140, height: 120)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 130 + 5 * 140 + 52, alignment: .leading)
        .background(Backdrop())
        .foregroundStyle(theme.nookForeground)
        write(content, size: NSSize(width: 130 + 5 * 140 + 52, height: CGFloat(rows.count) * 124 + 56), to: url)
    }

    // MARK: Cost

    /// Moves the gaze about at the page's throttled rate, as a pointer crossing the page does.
    @MainActor private final class Pointer: ObservableObject {
        @Published var gaze: CGPoint? = nil
        private var timer: Timer?
        private var step = 0
        func start() {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        private func advance() {
            step += 1
            gaze = CGPoint(x: CGFloat((step % 9) - 4) / 4, y: CGFloat(((step / 9) % 5) - 2) / 4)
        }
        func stop() { timer?.invalidate(); timer = nil }
    }

    private struct Stage: View {
        @ObservedObject var pointer: Pointer
        let mood: WispMood
        var body: some View { WispFace(mood: mood, size: 80, gaze: pointer.gaze) }
    }

    /// One cost case: what's hosted, and the switches it flips.
    private struct CostCase {
        let label: String
        var mood: WispMood = .idle
        var still = false
        var moving = false
        var content: Content = .face
        var blinking = true
        enum Content { case blank, face, page, pagePlain }
    }

    /// CPU over 12 s with each case in the same on-screen 620 x 300 window.
    private static func measureCost(to root: URL) {
        let theme = ThemeStore.shared
        var report: [String] = []
        let cases: [CostCase] = [
            CostCase(label: "blank view, no face (the runner's floor)", content: .blank),
            CostCase(label: "idle, live (blinks and glances)"),
            CostCase(label: "idle, live, blink and glance task off", blinking: false),
            CostCase(label: "pointer moving, live (gaze every 100 ms)", moving: true),
            CostCase(label: "speaking, live (mouth opening and closing)", mood: .speaking),
            CostCase(label: "page, a still Image in the face's place", content: .pagePlain),
            CostCase(label: "page with the face, idle, live", content: .page),
            CostCase(label: "idle, still (Reduce Motion)", still: true),
            CostCase(label: "speaking, still (Reduce Motion)", mood: .speaking, still: true),
            CostCase(label: "blank view again (the floor, after)", content: .blank),
        ]
        let wisp = WispModel.shared
        // The page captures before this leave work draining for a while (it read 14% with no
        // face at all); wait for 2 s slices under 3%, at most 60 s (the scope has 300 s in all), so the cases measure the face.
        let settleStart = Date()
        var slice = 100.0
        while slice >= 3, Date().timeIntervalSince(settleStart) < 60 {
            let before = FeatureQAHarness.cpuSeconds()
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            slice = (FeatureQAHarness.cpuSeconds() - before) / 2 * 100
        }
        report.append(String(format: "wisp-cost settled to %.1f%% after %.0f s before measuring", slice,
                             Date().timeIntervalSince(settleStart)))
        for item in cases {
            theme.reduceMotionPreference = item.still
            WispFaceCost.blinking = item.blinking
            WispPage.plainFace = item.content == .pagePlain
            wisp.setPreview([], mood: item.mood)
            let pointer = Pointer()
            let inner: AnyView
            switch item.content {
            case .blank: inner = AnyView(Color.clear.frame(width: 116, height: 92))
            case .face: inner = AnyView(Stage(pointer: pointer, mood: item.mood))
            case .page, .pagePlain: inner = AnyView(WispPage(model: wisp, onEditingChanged: { _ in }).padding(12))
            }
            // A blank view first and last shows any leftover work from the captures before
            // (pairing every case with one ran past the scope's 300 s limit).
            let own = cost(of: inner, pointer: item.moving ? pointer : nil)
            let line = String(format: "wisp-cost %@: %.1f%% CPU over 12 s", item.label, own)
            print(line)
            report.append(line)
        }
        WispFaceCost.blinking = true
        WispPage.plainFace = false
        wisp.setPreview([], mood: .idle)
        theme.reduceMotionPreference = false
        try? report.joined(separator: "\n").write(to: root.appendingPathComponent("motion-cost.txt"), atomically: true, encoding: .utf8)
    }

    /// CPU over 12 s with `content` in an on-screen 620 x 300 window, after 2 s to settle.
    private static func cost(of content: AnyView, pointer: Pointer?) -> Double {
        let theme = ThemeStore.shared
        let page = content
            .frame(width: 620, height: 300)
            .background(theme.notch.surface)
            .foregroundStyle(theme.nookForeground)
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 620, height: 300), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: page)
        window.orderFrontRegardless()
        pointer?.start()
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        let start = FeatureQAHarness.cpuSeconds()
        RunLoop.main.run(until: Date().addingTimeInterval(12))
        let value = (FeatureQAHarness.cpuSeconds() - start) / 12 * 100
        pointer?.stop()
        window.orderOut(nil)
        window.contentView = nil
        return value
    }

    // MARK: Drawing

    private static func offscreen<V: View>(_ view: V, size: NSSize) -> (NSHostingView<V>, NSWindow) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: ThemeStore.shared.nookScheme == .light ? .aqua : .darkAqua)
        window.contentView = host
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    private static func write<V: View>(_ view: V, size: NSSize, to url: URL) {
        let (host, window) = offscreen(view, size: size)
        defer { window.contentView = nil }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if let png = snapshot(host)?.representation(using: .png, properties: [:]) { try? png.write(to: url) }
    }

    /// The view drawn at `scale`, whatever the screen's own scale.
    private static func snapshot(_ host: NSView) -> NSBitmapImageRep? {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale),
                                            pixelsHigh: Int(host.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }
}
#endif
