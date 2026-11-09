#if DEBUG
import SwiftUI
import AppKit

/// The site's hero video (`reel`, in `WebsiteDemoClips`): 15 s, silent, looping on the closed
/// notch, drawn frame by frame at a fixed 60 fps (`clip(rendered:)`). It runs on the tour's stage
/// (the top of a 14-inch MacBook Pro's screen with the Night Blossom photo and a plain menu bar,
/// `WebsiteDemoNotch.crop` wide) with one big caption per beat at the bottom left:
/// the pointer opens the Nook on Music in Blossom and Put a Light On's line lands as a Poster;
/// the scenes whip through Firefly, Glacier, Midnight and Synthwave on the same page; the Nook
/// closes, the agent bubble slides out (framed close), a click opens the Agents tab and Allow
/// sends the session back to work; glass KemoSabe in Lavender hears "Can Sarah come over
/// tonight?" and the ask line arrives; a photo drops into the Tray and a Shift-drag opens the
/// converter wheel on JPG; Tape's strip glides two columns along (`WebsiteDemoTape`); then the
/// end card, MacSpaces' mark and "For Mac · macspaces.dev", as the Nook closes. Everything is
/// synthetic apart from the demo song and its cover.
@MainActor
enum WebsiteDemoReel {
    static let length = 15.0
    static let stage = WebsiteDemoNotch.stage
    static let wide = WebsiteDemoNotch.crop
    /// The poster's moment: the Music page with BRIGHT landed.
    static let posterAt = 3.3
    /// Close on the notch's row of bubbles for the agent bubble (520 points of the stage).
    static let close: CGRect = {
        let side = AgentPopoutLayout.bubbleSide(forHeight: WebsiteDemoProfile.notchSize.height)
        let centre = stage.width / 2 + AgentPopoutLayout.laneWidth(bubbles: 1, side: side) / 2
        return CGRect(x: centre - 260, y: 0, width: 520, height: 520 * wide.height / wide.width)
    }()

    /// Seconds of video.
    enum Beat {
        static let open = 0.7, lyric = 1.75
        static let whip: [(Double, ThemeFamily)] = [(4.4, .firefly), (4.8, .glacier), (5.2, .midnight), (5.6, .synthwave)]
        static let close = 6.0, out = 6.3, click = 7.0, allow = 7.85
        static let wisp = 8.5, ask = 8.7, think = 9.0, told = 9.55
        static let tray = 10.5, dragStart = 10.6, drop = 11.15, grab = 11.35, wheel = 11.75, jpg = 12.1
        static let tape = 12.5, tapeFrom = 0.75
        static let end = 14.0, shut = 14.35
    }

    struct Caption { let start: Double, end: Double, text: String }
    static let captions: [Caption] = [
        Caption(start: 0.15, end: 1.5, text: "Your notch."),
        Caption(start: 1.5, end: 4.0, text: "Plays your music,"),
        Caption(start: 4.0, end: 6.0, text: "in any look,"),
        Caption(start: 6.0, end: 8.5, text: "keeps your agents moving,"),
        Caption(start: 8.5, end: 10.5, text: "without giving away your life,"),
        Caption(start: 10.5, end: 12.5, text: "holds your files,"),
        Caption(start: 12.5, end: 14.0, text: "and lines up your windows."),
    ]

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func ease(_ t: Double, _ from: Double, _ to: Double) -> Double { WebsiteDemoAgents.ease(t, from: from, to: to) }

    /// What the video shows of the stage at `t`: the tour's framing, closing in on the agent
    /// bubble as the Nook closes and widening again as the click opens it.
    static func crop(at t: Double) -> CGRect {
        func mix(_ p: Double) -> CGRect {
            let p = CGFloat(p)
            return CGRect(x: wide.minX + (close.minX - wide.minX) * p, y: 0,
                          width: wide.width + (close.width - wide.width) * p,
                          height: wide.height + (close.height - wide.height) * p)
        }
        if t < Beat.close || t >= Beat.click + 0.5 { return wide }
        if t < Beat.click { return mix(ease(t, Beat.close, Beat.close + 0.45)) }
        return mix(1 - ease(t, Beat.click, Beat.click + 0.5))
    }

    /// Where the pointer rests while the bubble is out, on the desktop right of the notch.
    static let rest = CGPoint(x: 930, y: 205)
    /// The file dragged into the Tray: from the desktop to the Tray's first place.
    static let dragFrom = CGPoint(x: 1090, y: 420), dropAt = CGPoint(x: 640, y: 115)
    /// Where the Shift-drag opens the wheel, and the wheel's JPG wedge (filled in by `reel`).
    static let wheelCentre = CGPoint(x: 975, y: 290)
    static var jpgAngle = -90.0

    /// Readies the reel's Tray, files and agents, then draws it.
    static func render(output: URL, files: URL, sarah: WispMessage, told: WispMessage,
                       clip: (_ stage: @escaping (WebsiteDemoClips.Clock) -> AnyView,
                              _ setup: @escaping (WebsiteDemoClips.Clock, NotchViewModel, ShelfStore) -> Void,
                              _ beats: [WebsiteDemoClips.Beat]) async -> Void) async {
        let services = AppServices.shared, theme = ThemeStore.shared, wisp = WispModel.shared
        let monitor = AgentActivityMonitor.shared, popout = AgentPopout.shared, wheel = ConverterWheel.shared
        // The Tray: the picture pack's files (or drawn ones), then a photo dropped in.
        let folder = files.appendingPathComponent("Reel tray", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pack = WebsiteDemoClips.trayPackFiles(in: folder)
        var trayFiles = pack?.files ?? []
        if pack == nil {
            let lease = folder.appendingPathComponent("Lease summary.pdf")
            WebsiteDemoClips.writeLeasePDF(lease)
            let packing = folder.appendingPathComponent("Packing list.txt")
            try? "Packing list\nBoots, rain shell, map, headlamp, film camera".write(to: packing, atomically: true, encoding: .utf8)
            trayFiles = [lease, WebsiteDemoClips.writeInvoice(folder.appendingPathComponent("Scan 3.png")), packing]
        }
        let packBlossom = WebsiteDemoClips.folioPackFolder.appendingPathComponent("blossom.jpg")
        let picture = NSImage(contentsOf: packBlossom) ?? NSImage(named: "ThemeBlossom") ?? NSImage(size: NSSize(width: 1200, height: 800))
        // A camera-sized photo (1000 points wide), so its Tray preview is ready moments after the drop.
        let small = NSImage(size: NSSize(width: 1000, height: 1000 * max(picture.size.height, 1) / max(picture.size.width, 1)), flipped: false) { rect in
            picture.draw(in: rect); return true
        }
        let photo = WebsiteDemoClips.writePNG(small, folder.appendingPathComponent("Cherry blossom.png"))
        // Two Trays, every file read first (thumbnails, kinds and what Folio found): before the
        // drop, and after it with the photo first, as the app takes a drop. A preview requested
        // while frames are drawn arrives too late, so the drop moves the Nook onto the second.
        let shelf = ShelfStore(basketID: nil), dropped = ShelfStore(basketID: nil)
        shelf.setPreviewItems(trayFiles, selectedIndex: nil)
        dropped.setPreviewItems([photo] + trayFiles, selectedIndex: nil)
        await shelf.waitForFileMetadata()
        await dropped.waitForFileMetadata()
        for _ in 0..<300 where ([photo] + trayFiles).contains(where: { FolioIndex.shared.record(for: $0) == nil }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        FolioIndex.shared.setPreviewMarks(pack?.marks ?? [:])
        wheel.preview([photo], tools: false, hovered: nil)
        let jpg = wheel.actions.firstIndex { $0.title == "JPG" } ?? 0
        jpgAngle = Double(jpg) * 360 / Double(max(wheel.actions.count, 1)) - 90

        let savedSessions = monitor.sessions
        let savedTab = UserDefaults.standard.string(forKey: WidgetOptions.Keys.terminalTab)
        defer {
            monitor.preview(savedSessions); monitor.spotlight = nil
            popout.setPreview([], mood: .needsYou)
            FolioIndex.shared.setPreviewMarks([:])
            if let savedTab { UserDefaults.standard.set(savedTab, forKey: WidgetOptions.Keys.terminalTab) }
            else { UserDefaults.standard.removeObject(forKey: WidgetOptions.Keys.terminalTab) }
        }
        let model = WebsiteDemoProfile.model(availableWidth: stage.width, shelf: shelf)
        model.screenFrame = CGRect(origin: .zero, size: stage)
        let after = WebsiteDemoProfile.model(availableWidth: stage.width, shelf: dropped)
        after.screenFrame = model.screenFrame
        after.selectedTab = .tray
        after.state = .expanded
        let nook = Nook(model)
        // The agents' sessions count from the bubble's arrival, as the Agents video's do.
        let shift = Beat.out - WebsiteDemoAgents.outAt
        func sessions(_ t: Double) -> [AgentActivityMonitor.Session] {
            WebsiteDemoAgents.sessions(answered: t >= Beat.allow + 0.08, at: t - shift)
        }
        func spring(_ change: () -> Void) { withAnimation(Design.spring()) { change() } }

        var beats: [WebsiteDemoClips.Beat] = [
            (Beat.open, { _, _, _ in model.expand(to: .music) }),
            (Beat.lyric, { _, _, _ in
                let line = WebsiteDemoProfile.track("generationals")?.lyrics?.first ?? ""
                spring { services.teleprompter.setPreview(current: line, source: .lyrics) }
            }),
            (Beat.close, { _, _, _ in
                model.collapse()
                monitor.preview(sessions(Beat.close)); monitor.spotlight = nil
                popout.setPreview(monitor.sessions.filter { $0.state == .needsYou }, mood: .needsYou)
            }),
            // Out of sight while the Nook is closed: the Agents video's theme.
            (Beat.close + 0.5, { _, _, _ in theme.selectFamily(.nightBlossom) }),
            (Beat.click + 0.08, { _, _, _ in monitor.spotlight = "b"; model.expand(to: .terminal) }),
            (Beat.allow + 0.08, { _, _, _ in popout.setPreview([], mood: .needsYou) }),
            (Beat.wisp, { _, _, _ in
                monitor.spotlight = nil
                wisp.setPreview([], mood: .idle)
                spring { theme.selectFamily(.lavender); model.selectedTab = .wisp }
            }),
            (Beat.ask, { _, _, _ in wisp.setPreview([sarah], mood: .listening) }),
            (Beat.think, { _, _, _ in wisp.setPreview([sarah], mood: .thinking) }),
            (Beat.told, { _, _, _ in wisp.setPreview([sarah, told], mood: .thinking) }),
            (Beat.tray, { _, _, _ in spring { theme.selectFamily(.blossom); model.selectedTab = .tray } }),
            (Beat.drop, { _, _, _ in nook.model = after }),
            (Beat.wheel, { _, _, _ in wheel.preview([photo], tools: false, hovered: nil) }),
            (Beat.jpg, { _, _, _ in withAnimation(Design.spring()) { wheel.hovered = jpg } }),
            // Behind Tape's strip: back to Home, ready for the end card.
            (Beat.tape + 0.3, { _, _, _ in
                theme.selectFamily(.blossom); after.selectedTab = .nook
                wisp.setPreview([], mood: .idle)
                wheel.preview([photo], tools: false, hovered: nil)
            }),
            (Beat.shut, { _, _, _ in after.collapse() }),
        ]
        for (at, family) in Beat.whip { beats.append((at, { _, _, _ in theme.selectFamily(family) })) }
        // While the Agents tab shows, the sessions' times follow the video's clock, frame by frame.
        let fps = WebsiteDemo234.fps
        for n in Int(Beat.click * fps)..<Int(Beat.wisp * fps) {
            let t = Double(n) / fps
            beats.append((t, { _, _, _ in monitor.preview(sessions(t)) }))
        }
        beats.sort { $0.0 < $1.0 }
        await clip({ clock in AnyView(Stage(nook: nook, clock: clock)) }, { _, _, _ in
            theme.selectFamily(.blossom)
            theme.setPreviewSystemReduceMotion(false)
            WebsiteDemoProfile.play(WebsiteDemoProfile.track("generationals"))
            services.teleprompter.setPreview(current: "", source: .lyrics)
            // No running timers and no Keep Awake: only the song's cover sits beside the notch.
            for timer in services.allTimers { timer.setPreview(remaining: 0, total: WebsiteDemoProfile.timerTotal) }
            services.keepAwake.stop()
            UserDefaults.standard.set(CodingPanel.Tab.agents.rawValue, forKey: WidgetOptions.Keys.terminalTab)
            monitor.preview(sessions(0)); monitor.spotlight = nil
            popout.setPreview([], mood: .needsYou)
            wisp.setPreview([], mood: .idle)
        }, beats)
    }

    /// The whole frame: the tour's stage at `crop(at:)`, Tape's strip, the end card and the caption.
    /// The Nook on the stage; the drop moves it onto the Tray that holds the photo.
    final class Nook: ObservableObject {
        @Published var model: NotchViewModel
        init(_ model: NotchViewModel) { self.model = model }
    }

    struct Stage: View {
        @ObservedObject var nook: Nook
        @ObservedObject var clock: WebsiteDemoClips.Clock

        var body: some View {
            let t = clock.t
            let size = WebsiteDemoClips.stage
            let crop = WebsiteDemoReel.crop(at: t)
            let scale = size.width / crop.width
            // Tape's strip cuts in quickly and out to the end card.
            let tape = clamp((t - Beat.tape) / 0.12) * (1 - clamp((t - Beat.end) / 0.12))
            ZStack(alignment: .topLeading) {
                NotchScene(model: nook.model, clock: clock)
                    .offset(x: -crop.minX, y: -crop.minY)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                if tape > 0 {
                    WebsiteDemoTape.Stage(clock: clock, from: Beat.tapeFrom - Beat.tape, keys: false)
                        .opacity(tape)
                }
                // A soft shade at the bottom, so the caption reads over any scene.
                LinearGradient(colors: [.clear, .black.opacity(0.34)], startPoint: .top, endPoint: .bottom)
                    .frame(width: size.width, height: 150)
                    .offset(y: size.height - 150)
                EndCard(t: t)
                CaptionLine(t: t)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }
    }

    /// One caption per beat, bottom left: each word slides up and fades in, a little after the last.
    struct CaptionLine: View {
        let t: Double

        var body: some View {
            if let caption = WebsiteDemoReel.captions.first(where: { t >= $0.start && t < $0.end }) {
                let words = caption.text.split(separator: " ").map(String.init)
                let leaving = clamp((t - (caption.end - 0.14)) / 0.14)
                HStack(spacing: 7) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        let raw = clamp((t - caption.start - Double(index) * 0.05) / 0.25)
                        let p = 1 - pow(1 - raw, 3)
                        Text(word)
                            .opacity(p * (1 - leaving))
                            .offset(y: CGFloat((1 - p) * 18 - leaving * 10))
                    }
                }
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 9, y: 2)
                .fixedSize()
                .padding(.leading, 30).padding(.bottom, 28)
                .frame(width: WebsiteDemoClips.stage.width, height: WebsiteDemoClips.stage.height, alignment: .bottomLeading)
            }
        }
    }

    /// MacSpaces' mark and where to get it, over the desktop as the Nook closes.
    struct EndCard: View {
        let t: Double

        var body: some View {
            let shown = clamp((t - Beat.end - 0.05) / 0.2) * (1 - clamp((t - (length - 0.32)) / 0.26))
            if shown > 0 {
                let p = 1 - pow(1 - shown, 3)
                ZStack {
                    Color.black.opacity(0.28 * p)
                    card(p).offset(y: 70)
                }
                .frame(width: WebsiteDemoClips.stage.width, height: WebsiteDemoClips.stage.height)
            }
        }

        private func card(_ p: Double) -> some View {
                HStack(spacing: 16) {
                    MacSpacesMark(size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MacSpaces").font(.system(size: 34, weight: .bold))
                        Text("For Mac · macspaces.dev").font(.system(size: 19, weight: .medium)).opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
                .opacity(p)
                .offset(y: CGFloat((1 - p) * 14))
        }
    }

    /// The tour's desktop, menu bar, Nook and camera, with the agent bubble where its panel would
    /// be, the pointer, a file being dragged and the converter wheel, in stage points.
    struct NotchScene: View {
        @ObservedObject var model: NotchViewModel
        @ObservedObject var clock: WebsiteDemoClips.Clock
        @ObservedObject private var popout = AgentPopout.shared
        @ObservedObject private var wheel = ConverterWheel.shared

        var body: some View {
            let size = WebsiteDemoReel.stage
            let t = clock.t
            ZStack(alignment: .topLeading) {
                Image("ThemeNightBlossom").resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
                    .overlay(Color.black.opacity(0.2))
                // Inside what the video shows: the Apple and Finder menus beside the notch's bubbles
                // in the tour's framing, only the clock when close on the agent bubble.
                let crop = WebsiteDemoReel.crop(at: t)
                DemoMenuBar(height: model.geometry.height, within: crop.minX...crop.maxX, sparse: true,
                            menus: [], appMenu: crop.width > wide.width * 0.9)
                    .frame(width: size.width)
                NotchContainerView(viewModel: model)
                    .frame(width: size.width, height: size.height, alignment: .top)
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                    .fill(.black).frame(width: model.geometry.width, height: model.geometry.height)
                    .frame(width: size.width, alignment: .top)
                bubble
                if t >= Beat.wheel, t < Beat.tape + 0.2 {
                    ConverterWheelView(wheel: wheel)
                        .position(wheelCentre)
                }
                if let drag = dragged {
                    DraggedPhoto(small: drag.small)
                        .position(drag.point)
                }
                if let pointer = pointerState {
                    cursor(pointer.point, pressed: pointer.pressed, opacity: pointer.opacity)
                    if t >= Beat.grab, t < Beat.tape {
                        ShiftKey().position(x: pointer.point.x + 34, y: pointer.point.y + 34)
                            .opacity(clamp((t - Beat.grab) / 0.12))
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }

        /// The agent bubble sliding out from under the notch's edge (0.38 s, `AgentPopout.show`)
        /// and tucking back quickly as the click opens the Nook.
        private var bubbleState: (frame: CGRect, alpha: Double)? {
            guard let notch = model.closedNotchFrame else { return nil }
            let screen = CGRect(origin: .zero, size: WebsiteDemoReel.stage)
            let target = AgentPopoutLayout.frame(besideNotch: notch, on: screen)
            let tucked = AgentPopoutLayout.startFrame(besideNotch: notch)
            let t = clock.t, hideAt = Beat.click + 0.08
            func mix(_ p: Double) -> CGRect { target.offsetBy(dx: (tucked.minX - target.minX) * (1 - p), dy: 0) }
            if t < Beat.out { return nil }
            if t < hideAt {
                let linear = (t - Beat.out) / 0.38
                let p = WebsiteDemoAgents.bezier(linear, 0.2, 0.9, 0.25, 1.05)
                return (mix(linear >= 1 ? 1 : p), clamp(p))
            }
            let hide = (t - hideAt) / 0.12
            guard hide < 1 else { return nil }
            let p = 1 - WebsiteDemoAgents.bezier(hide, 0.42, 0, 0.58, 1)
            return (mix(p), p)
        }

        @ViewBuilder private var bubble: some View {
            if let state = bubbleState {
                AgentPopoutView(popout: popout, stillTime: max(0, clock.t - Beat.out))
                    .frame(width: state.frame.width, height: state.frame.height)
                    .opacity(state.alpha)
                    .position(x: state.frame.midX, y: WebsiteDemoReel.stage.height - state.frame.midY)
            }
        }

        private var bubblePoint: CGPoint {
            guard let notch = model.closedNotchFrame else { return rest }
            let target = AgentPopoutLayout.frame(besideNotch: notch, on: CGRect(origin: .zero, size: WebsiteDemoReel.stage))
            return CGPoint(x: target.midX, y: WebsiteDemoReel.stage.height - target.midY + 3)
        }

        private var jpgPoint: CGPoint {
            let angle = jpgAngle * .pi / 180
            let radius = (ConverterWheel.innerRadius + ConverterWheel.outerRadius) / 2 + 10
            return CGPoint(x: wheelCentre.x + cos(angle) * radius + 6, y: wheelCentre.y + sin(angle) * radius + 10)
        }

        /// A hand's path from `a` to `b`, with a slight arc.
        private func path(_ a: CGPoint, _ b: CGPoint, _ from: Double, _ to: Double) -> CGPoint {
            let p = ease(clock.t, from, to)
            let lift = sin(p * .pi) * 16
            return CGPoint(x: a.x + (b.x - a.x) * p + lift * 0.4, y: a.y + (b.y - a.y) * p - lift)
        }

        /// The pointer: to the notch (which opens), to the agent bubble and Allow, and with the
        /// file out of the Tray onto the wheel's JPG. Hidden between, and at both ends, so it loops.
        private var pointerState: (point: CGPoint, pressed: Bool, opacity: Double)? {
            let t = clock.t
            let notch = CGPoint(x: WebsiteDemoReel.stage.width / 2 + 6, y: 20)
            let start = CGPoint(x: 960, y: 330)
            let allow = WebsiteDemoAgents.fallbackAllow
            if t < 1.4 {
                let point = t < 0.15 ? start : t < 0.65 ? path(start, notch, 0.15, 0.65) : notch
                return (point, false, clamp((t - 0.02) / 0.12) * (1 - clamp((t - 1.05) / 0.25)))
            }
            if t >= Beat.close + 0.1, t < Beat.wisp {
                let point: CGPoint
                if t < Beat.out + 0.25 { point = rest }
                else if t < Beat.click - 0.05 { point = path(rest, bubblePoint, Beat.out + 0.25, Beat.click - 0.05) }
                else if t < Beat.click + 0.3 { point = bubblePoint }
                else if t < Beat.allow - 0.05 { point = path(bubblePoint, allow, Beat.click + 0.3, Beat.allow - 0.05) }
                else if t < Beat.allow + 0.2 { point = allow }
                else { point = path(allow, CGPoint(x: allow.x + 120, y: allow.y + 150), Beat.allow + 0.2, Beat.wisp) }
                let pressed = (Beat.click..<Beat.click + 0.14).contains(t) || (Beat.allow..<Beat.allow + 0.14).contains(t)
                return (point, pressed, clamp((t - Beat.close - 0.1) / 0.15) * (1 - clamp((t - Beat.wisp + 0.25) / 0.2)))
            }
            if t >= Beat.drop, t < Beat.tape + 0.05 {
                let point: CGPoint
                if t < Beat.grab { point = dropAt }
                else if t < Beat.wheel { point = path(dropAt, wheelCentre, Beat.grab, Beat.wheel) }
                else if t < Beat.wheel + 0.1 { point = wheelCentre }
                else if t < Beat.jpg { point = path(wheelCentre, jpgPoint, Beat.wheel + 0.1, Beat.jpg) }
                else { point = jpgPoint }
                let pressed = (Beat.grab..<Beat.grab + 0.12).contains(t)
                return (point, pressed, 1)
            }
            return nil
        }

        /// The file on its way into the Tray (with the pointer drawn in), then pulled out of it.
        private var dragged: (point: CGPoint, small: Bool)? {
            let t = clock.t
            if t >= Beat.dragStart, t < Beat.drop {
                let raw = clamp((t - Beat.dragStart) / (Beat.drop - Beat.dragStart))
                let p = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2
                return (CGPoint(x: dragFrom.x + (dropAt.x - dragFrom.x) * p, y: dragFrom.y + (dropAt.y - dragFrom.y) * p), false)
            }
            if t >= Beat.grab + 0.08, t < Beat.wheel, let pointer = pointerState {
                return (CGPoint(x: pointer.point.x - 4, y: pointer.point.y - 4), true)
            }
            return nil
        }

        private func cursor(_ point: CGPoint, pressed: Bool, opacity: Double) -> some View {
            let cursor = NSCursor.arrow
            let image = cursor.image
            return Image(nsImage: image)
                .frame(width: image.size.width, height: image.size.height)
                .scaleEffect(pressed ? 0.86 : 1, anchor: UnitPoint(x: cursor.hotSpot.x / image.size.width, y: cursor.hotSpot.y / image.size.height))
                .opacity(opacity)
                .position(x: point.x - cursor.hotSpot.x + image.size.width / 2, y: point.y - cursor.hotSpot.y + image.size.height / 2)
        }
    }

    /// A photo being dragged: its thumbnail and name, as Finder draws a drag.
    struct DraggedPhoto: View {
        let small: Bool

        var body: some View {
            let picture = NSImage(contentsOf: WebsiteDemoClips.folioPackFolder.appendingPathComponent("blossom.jpg")) ?? NSImage(named: "ThemeBlossom")
            VStack(spacing: 4) {
                Group {
                    if let picture { Image(nsImage: picture).resizable().scaledToFill() } else { Color.pink }
                }
                .frame(width: small ? 46 : 74, height: small ? 34 : 54).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 7, y: 3)
                if !small {
                    Text("Cherry blossom.png")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.white)
                }
            }
            .opacity(0.92)
            .overlay(alignment: .topLeading) {
                if !small {
                    Image(nsImage: NSCursor.arrow.image).offset(x: 30, y: 22)
                }
            }
        }
    }

    /// Shift held while dragging, beside the pointer.
    struct ShiftKey: View {
        var body: some View {
            Text("⇧ Shift").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

extension WebsiteDemoClips {
    /// The site's hero video (`WebsiteDemoReel`), drawn frame by frame at a fixed rate.
    static func reel(output: URL, files: URL, sarah: WispMessage, told: WispMessage) async {
        await WebsiteDemoReel.render(output: output, files: files, sarah: sarah, told: told) { stage, setup, beats in
            // Its busiest pages come after the closed notch it's timed on, so time runs slower still.
            await clip("reel", length: WebsiteDemoReel.length, output: output, tab: .wisp, rendered: true, onScreen: true,
                       costFactor: 4, stageView: stage, setup: setup, beats: beats)
        }
    }
}
#endif
