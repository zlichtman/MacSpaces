import AppKit
import Combine
import SwiftUI

/// The agent bubble: the agent's app icon in a round bubble that slides out from the side
/// of the closed notch while a coding agent needs you, its accent ring breathing, and
/// (Settings → Activities → Show the bubble while agents work) while one works or just
/// finished (`AgentPopoutLayout` decides where and when, `AgentFace` its state). It stays at the top of the screen,
/// out of the way: no card drops over your windows. Clicking it opens the Terminal
/// page's Agents tab on that session; its menu also goes to the agent's app. It's
/// hidden from screen sharing and recordings.
@MainActor
final class AgentPopout: ObservableObject {
    static let shared = AgentPopout()

    /// Sessions that need you, oldest first, and sessions working, newest first.
    @Published private(set) var waiting: [AgentActivityMonitor.Session] = []
    @Published private(set) var working: [AgentActivityMonitor.Session] = []
    /// The session that last finished, whose icon the tick shows on.
    @Published private(set) var finished: AgentActivityMonitor.Session?
    /// What the face shows while on screen.
    @Published private(set) var mood: AgentFace.Mood = .needsYou
    /// Drives the motion only while the bubble is on screen.
    @Published private(set) var isShown = false
    /// The bubble's frame on screen, while shown (the notch's hover check skips it).
    private(set) var frame: NSRect?

    private var panel: NSPanel?
    private var hiddenForApp = false
    private var locked = false
    /// Each session's last state, to notice one finishing; and until when the tick shows.
    private var lastStates: [String: AgentActivityMonitor.Session.State] = [:]
    private var cheerUntil: Date?
    private var cheerTimer: Timer?
    private var sessionsWatch: AnyCancellable?
    private var settingWatch: AnyCancellable?
    private var lockObservers: [NSObjectProtocol] = []

    private var isRealApp: Bool { Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" }

    func start() {
        guard sessionsWatch == nil else { return }
        sessionsWatch = AgentActivityMonitor.shared.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in self?.update(sessions) }
        settingWatch = AgentActivityMonitor.shared.$peekWhileWorking
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            lockObservers.append(center.addObserver(forName: .init(name), object: nil, queue: .main) { note in
                Task { @MainActor in
                    AgentPopout.shared.locked = note.name.rawValue == "com.apple.screenIsLocked"
                    AgentPopout.shared.refresh()
                }
            })
        }
    }

    private func update(_ sessions: [AgentActivityMonitor.Session]) {
        let now = sessions.filter { $0.state == .needsYou }.sorted { $0.updated < $1.updated }
        // A tap on the trackpad when a new one starts waiting (if haptics are on).
        if now.contains(where: { session in !waiting.contains { $0.id == session.id } }) { Haptics.tap() }
        if now != waiting { waiting = now }
        let busy = sessions.filter { $0.state == .working }.sorted { $0.updated > $1.updated }
        if busy != working { working = busy }
        // One that was working or waiting has finished: smile for a moment.
        let done = sessions.first { $0.state == .done && (lastStates[$0.id].map { $0 != .done } ?? false) }
        lastStates = Dictionary(sessions.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })
        if let done { finished = done; cheer() }
        refresh()
    }

    private func cheer() {
        cheerUntil = Date().addingTimeInterval(AgentFace.cheerDuration)
        cheerTimer?.invalidate()
        let timer = Timer(timeInterval: AgentFace.cheerDuration + 0.05, repeats: false) { _ in
            Task { @MainActor in
                AgentPopout.shared.cheerUntil = nil
                AgentPopout.shared.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cheerTimer = timer
    }

    /// "Hide in" apps (`NotchManager`): it steps aside while one is in front.
    func setHiddenForApp(_ hidden: Bool) {
        guard hidden != hiddenForApp else { return }
        hiddenForApp = hidden
        refresh()
    }

    /// Shows, moves or hides it for the current state; `NotchManager` calls this when a
    /// Nook opens or closes and when the closed notch changes width.
    func refresh() {
        guard isRealApp else { return }
        let anchor = NotchManager.active?.agentAnchor()
        let monitor = AgentActivityMonitor.shared
        let context = AgentPopoutLayout.Context(waiting: waiting.count, working: working.count,
                                                cheering: cheerUntil.map { $0 > Date() } ?? false,
                                                whileWorking: monitor.peekWhileWorking, enabled: monitor.isEnabled,
                                                locked: locked, hiddenForApp: hiddenForApp, nookOpen: anchor?.nookOpen ?? true)
        let nookWasOpen = self.nookWasOpen
        self.nookWasOpen = context.nookOpen
        returnAfterClose?.cancel(); returnAfterClose = nil
        // Opening: tucked away before the panel widens past it. Closing: back out once
        // the panel has drawn in, so the two never cross.
        guard let anchor, AgentPopoutLayout.isVisible(context), let next = AgentPopoutLayout.mood(context) else {
            hide(quickly: context.nookOpen); return
        }
        if next != mood { mood = next }
        let target = AgentPopoutLayout.frame(besideNotch: anchor.notch, on: anchor.screen)
        let start = AgentPopoutLayout.startFrame(besideNotch: anchor.notch)
        guard nookWasOpen, !isShown, !reduceMotion else { show(at: target, from: start); return }
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        returnAfterClose = work
        self.nookWasOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + Design.closeSettle, execute: work)
    }

    private var nookWasOpen = false
    private var returnAfterClose: DispatchWorkItem?

#if DEBUG
    /// Captures: these sessions, in this mood (nothing is shown on screen); `shown` as if on screen.
    func setPreview(_ sessions: [AgentActivityMonitor.Session], mood: AgentFace.Mood = .needsYou, shown: Bool = false) {
        waiting = sessions.filter { $0.state == .needsYou }
        working = sessions.filter { $0.state == .working }
        self.mood = mood
        isShown = shown
    }

    /// Captures: the bubble's move from `from` to `to`, as `show(at:)` makes it on screen.
    static func previewMove(from: CGRect, to: CGRect, _ apply: () -> Void) {
        guard !ThemeStore.shared.reduceMotion, abs(from.minX - to.minX) < 240 else { apply(); return }
        withAnimation(Design.laneAnimation(arriving: to.minX > from.minX)) { apply() }
    }

    /// Captures: the tick, on this session's icon.
    func setPreviewFinished(_ session: AgentActivityMonitor.Session?) { finished = session }
#endif

    /// Clicking it: the Agents tab on the session that's waited longest, else the
    /// newest working one.
    func open() {
        NotchManager.active?.openAgents(session: (waiting.first ?? working.first)?.id)
    }


    private var reduceMotion: Bool {
        ThemeStore.shared.reduceMotion
    }

    private func show(at target: NSRect, from start: NSRect) {
        let panel = self.panel ?? make()
        self.panel = panel
        frame = target
        guard !isShown else {
            if panel.frame != target { move(panel, to: target) }
            return
        }
        isShown = true
        // Slides out from under the notch's edge (or just fades in under Reduce Motion).
        panel.setFrame(reduceMotion ? target : start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.2 : 0.38
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.05)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    /// The closed row gained or lost an activity: the bubble moves with its edge on the
    /// row's own curve (`Design.laneAnimation`), out as an activity arrives and in as one
    /// leaves; under Reduce Motion it fades out and back in at its new place. A move to
    /// another screen (or a long way) is a jump.
    private func move(_ panel: NSPanel, to target: NSRect) {
        let from = panel.frame
        guard abs(from.minY - target.minY) < 1, abs(from.minX - target.minX) < 240 else {
            panel.setFrame(target, display: true); return
        }
        if reduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.08
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.isShown, self.frame == target else { return }
                    panel.setFrame(target, display: true)
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.08
                        panel.animator().alphaValue = 1
                    }
                }
            })
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Design.laneDuration * Design.demoTimeScale
            context.timingFunction = Design.laneTimingFunction(arriving: target.minX > from.minX)
            panel.animator().setFrame(target, display: true)
        }
    }

    private func hide(quickly: Bool = false) {
        frame = nil
        guard isShown, let panel else { return }
        isShown = false
        let tucked = NotchManager.active?.agentAnchor().map { AgentPopoutLayout.startFrame(besideNotch: $0.notch) }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = quickly ? 0.12 : 0.22
            if let tucked, !reduceMotion { panel.animator().setFrame(tucked, display: true) }
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in if self?.isShown == false { panel.orderOut(nil) } }
        })
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: AgentPopoutView(popout: self))
        return panel
    }
}

/// The bubble: the notch's black with the agent's app icon. While an agent needs you an
/// accent ring breathes around it (a count when more than one waits); while one works the
/// ring is fainter and slower; when one finishes it shows a green tick.
struct AgentPopoutView: View {
    @ObservedObject var popout: AgentPopout
    /// Debug captures draw it at one moment of the breath (0…1)…
    var stillPulse: Double?
    /// …or at one moment of its motion, in seconds.
    var stillTime: Double?
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Group {
                if let still = stillTime ?? stillPulse.map(Self.time(atPulse:)) {
                    bubble(side: side, time: still, moving: true)
                } else if popout.isShown && !theme.reduceMotion {
                    // The ring breathes in Core Animation, in the window server; a 24 fps
                    // timeline redrew the bubble for as long as an agent waited.
                    bubble(side: side, time: 0, moving: true, breathing: true)
                } else {
                    bubble(side: side, time: 0, moving: false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .contentShape(Circle())
        .onTapGesture { popout.open() }
        .contextMenu {
            // The longest-waiting permission request, answered without opening anything.
            if let session = popout.waiting.first(where: { $0.request != nil }), let request = session.request {
                Text("\(session.name) in \(session.project): \(request.detail.map { "\(request.title): \($0.prefix(60))" } ?? request.title)")
                Button("Allow") { AgentActivityMonitor.shared.answer(session, .allow) }
                Button("Deny") { AgentActivityMonitor.shared.answer(session, .deny) }
                Divider()
            }
            Button("Open Agents") { popout.open() }
            if let session = popout.waiting.first ?? popout.working.first,
               let app = session.appName ?? (session.appBundleID.isEmpty ? nil : "its app") {
                Button("Go to \(app)") { AgentActivityMonitor.shared.reveal(session) }
            }
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { popout.open() }
    }

    /// The moment in the breath that has this pulse (0 at rest, 1 at its fullest).
    private static func time(atPulse pulse: Double) -> Double {
        acos(1 - 2 * min(max(pulse, 0), 1)) / (2 * .pi) * 1.6
    }

    private var summary: String {
        AgentFace.summary(mood: popout.mood, waiting: popout.waiting.map { ($0.name, $0.project) },
                          working: popout.working.map { ($0.name, $0.project) })
    }

    private var help: String {
        switch popout.mood {
        case .needsYou:
            guard let first = popout.waiting.first else { return "" }
            let why = popout.waiting.count == 1 ? (first.note ?? first.headline) : summary
            return why + ". Click to open Agents; right-click to Allow or Deny."
        case .working:
            let doing = popout.working.count == 1 ? popout.working.first.map { "\(summary): \($0.headline)" } ?? summary : summary
            return doing + ". Click to open Agents."
        case .cheering:
            return "\(summary). Click to open Agents."
        }
    }

    /// The agent's own app icon (Claude, Codex; else the app it runs in) in the bubble, with
    /// the accent ring breathing: fully while one needs you, softly while one works; a
    /// green tick when one has just finished, and a count when several need you. `breathing`
    /// leaves the ring to `AgentPulseRing`, which breathes the same way by itself.
    private func bubble(side: CGFloat, time: Double, moving: Bool, breathing: Bool = false) -> some View {
        let accent = theme.notch.accent
        let mood = popout.mood
        let pulse = moving ? AgentPopoutLayout.pulse(at: mood == .working ? time * 0.6 : time) : 0.6
        let breath = AgentPulseRing.Breath(mood: mood, accent: NSColor(accent))
        let ring: Color
        switch mood {
        case .needsYou: ring = accent.opacity(0.45 + 0.55 * pulse)
        case .working: ring = accent.opacity(0.15 + 0.35 * pulse)
        case .cheering: ring = Color.green.opacity(0.8)
        }
        return NotchBubble(side: side, ring: breathing ? .clear : ring,
                           ringWidth: mood == .working ? 1 + 0.8 * pulse : 1.5 + 1.2 * pulse) {
            if breathing {
                AgentPulseRing(breath: breath).frame(width: side, height: side).allowsHitTesting(false)
            }
            icon(side: side * 0.58)
            badge(side: side, accent: accent)
                .frame(width: side, height: side, alignment: .bottomTrailing)
        }
        .frame(width: side, height: side)
    }

    /// The session the bubble is about: the first that needs you, else the first working.
    /// The session the bubble is about: the first that needs you, else the first working,
    /// else (showing the tick) the one that just finished.
    private var session: AgentActivityMonitor.Session? {
        popout.waiting.first ?? popout.working.first ?? popout.finished
    }

    /// Always the agent's own app icon (or the app it runs in): never a stand-in symbol.
    private func icon(side: CGFloat) -> some View {
        Image(nsImage: AgentActivityMonitor.agentIcon(for: session))
            .resizable().interpolation(.high).frame(width: side, height: side)
    }

    /// Bottom right: how many need you, or a tick when one is done.
    @ViewBuilder
    private func badge(side: CGFloat, accent: Color) -> some View {
        let size = side * 0.36
        switch popout.mood {
        case .needsYou where popout.waiting.count > 1:
            Text("\(popout.waiting.count)")
                .font(.system(size: max(8, side * 0.28), weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color.black)
                .padding(.horizontal, 3)
                .frame(minWidth: size, minHeight: size)
                .background(accent, in: Capsule())
        case .cheering:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.55, weight: .heavy))
                .foregroundStyle(Color.black)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.green))
                .overlay(Circle().strokeBorder(Color.black, lineWidth: 1))
        default:
            EmptyView()
        }
    }
}

/// The agent bubble's ring, breathing as `AgentPopoutLayout.pulse` does in each mood, as
/// one repeating layer animation: needs you (1.6 s, 1.5…2.7 pt inside the edge, 45…100%
/// of the accent), working (the same breath at 0.6 speed, 1…1.8 pt, 15…50%), cheering
/// (green at 80%, its width breathing as needs you).
private struct AgentPulseRing: NSViewRepresentable {
    struct Breath: Equatable {
        var color: NSColor
        var opacity: ClosedRange<Double>
        var width: ClosedRange<CGFloat>
        var period: Double

        init(mood: AgentFace.Mood, accent: NSColor) {
            switch mood {
            case .needsYou: self.init(color: accent, opacity: 0.45...1, width: 1.5...2.7, period: 1.6)
            case .working: self.init(color: accent, opacity: 0.15...0.5, width: 1...1.8, period: 1.6 / 0.6)
            case .cheering: self.init(color: .systemGreen, opacity: 0.8...0.8, width: 1.5...2.7, period: 1.6)
            }
        }

        init(color: NSColor, opacity: ClosedRange<Double>, width: ClosedRange<CGFloat>, period: Double) {
            self.color = color; self.opacity = opacity; self.width = width; self.period = period
        }
    }
    let breath: Breath

    func makeNSView(context: Context) -> AgentPulseRingView { AgentPulseRingView() }
    func updateNSView(_ view: AgentPulseRingView, context: Context) { view.breath = breath }
}

private final class AgentPulseRingView: NSView {
    private let ring = CAShapeLayer()
    var breath = AgentPulseRing.Breath(mood: .needsYou, accent: .white) {
        didSet { if breath != oldValue { breathingIn = .zero; fit() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        ring.fillColor = nil
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A window that was ordered out (or a Mac that slept) can drop the animation.
        if window != nil, ring.animation(forKey: "pulse") == nil { breathingIn = .zero }
        fit()
    }

    /// SwiftUI sizes the view by its frame, which doesn't ask for layout.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fit()
    }

    override func layout() {
        super.layout()
        fit()
    }

    private var breathingIn = CGRect.zero

    /// The ring fills the view and breathes; restarted only for a new size.
    private func fit() {
        guard !bounds.isEmpty, bounds != breathingIn else { return }
        breathingIn = bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ring.frame = bounds
        CATransaction.commit()
        breathe()
    }

    /// The stroke stays inside the edge as it thickens, as `strokeBorder` draws it.
    private func path(width: CGFloat) -> CGPath {
        let inset = 1 + width / 2
        return CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
    }

    private func breathe() {
        guard !bounds.isEmpty else { return }
        ring.removeAnimation(forKey: "pulse")
        let low = breath.width.lowerBound, high = breath.width.upperBound
        ring.strokeColor = breath.color.cgColor
        ring.path = path(width: low); ring.lineWidth = low; ring.opacity = Float(breath.opacity.lowerBound)
        func animate(_ key: String, _ from: Any, _ to: Any) -> CABasicAnimation {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = from; animation.toValue = to
            return animation
        }
        let group = CAAnimationGroup()
        group.animations = [animate("path", path(width: low), path(width: high)),
                            animate("lineWidth", low, high),
                            animate("opacity", breath.opacity.lowerBound, breath.opacity.upperBound)]
        // Half a breath each way; this curve is close to the cosine's.
        group.duration = breath.period / 2
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.37, 0, 0.63, 1)
        ring.add(group, forKey: "pulse")
    }
}

/// A round bubble beside the camera: the agent bubble, and in the clear look each
/// closed activity. Black, with a ring that is whole or, given `progress` (0…1), a
/// track filled clockwise from the top, and the content centred on top.
struct NotchBubble<Content: View>: View {
    let side: CGFloat
    let ring: Color
    var progress: Double?
    var ringWidth: CGFloat = 1.5
    /// A continuous-corner rounded square, like an album cover (the song and its sound),
    /// instead of a circle.
    var squircle = false
    /// With `progress`, the faint full ring under the arc.
    var track = true
    @ViewBuilder let content: Content

    /// The squircle's corner radius at a given size, shared with what it clips.
    static func squircleRadius(_ size: CGFloat) -> CGFloat { size * 0.28 }

    var body: some View {
        Group {
            if squircle {
                bubble(RoundedRectangle(cornerRadius: Self.squircleRadius(side), style: .continuous), turn: 0)
            } else {
                bubble(Circle(), turn: -90)
            }
        }
        .frame(width: side, height: side)
    }

    /// The black backing, the ring (whole, or a track filled from the top) and the
    /// content, all in `shape`.
    private func bubble<S: InsettableShape>(_ shape: S, turn: Double) -> some View {
        ZStack {
            shape.fill(Color.black)
            if let progress {
                if track { shape.inset(by: 1 + ringWidth / 2).stroke(ring.opacity(0.22), lineWidth: ringWidth) }
                shape.inset(by: 1 + ringWidth / 2).trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(ring, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(turn))
            } else {
                shape.inset(by: 1).strokeBorder(ring, lineWidth: ringWidth)
            }
            content
        }
    }
}
