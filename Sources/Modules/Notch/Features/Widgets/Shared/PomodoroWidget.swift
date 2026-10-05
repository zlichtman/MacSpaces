import SwiftUI
import AppKit
import Combine

/// Focus and break sessions with a progress ring and explicit controls.
/// The session lives in a shared model, so it keeps counting while the Nook
/// is closed and matches across displays.
struct PomodoroWidget: View {
    var compact = false
    @ObservedObject private var model = PomodoroModel.shared

    private var tint: Color { model.phase == .work ? .red : .green }

    var body: some View {
        if compact { compactBody } else { regularBody }
    }

    /// Time and phase on top, play/pause and skip below, so a stacked
    /// tile never truncates the time.
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                WidgetRing(progress: model.progress, tint: tint, lineWidth: 3).frame(width: 16, height: 16)
                Text(model.timeText)
                    .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(model.phase.title).font(.system(size: 9, weight: .semibold)).foregroundStyle(tint)
                    .lineLimit(1)
            }
            HStack(spacing: 5) {
            Button { model.toggle() } label: {
                Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .frame(width: 24, height: 24)
                    .background(ThemeStore.shared.notch.accent, in: Circle())
            }
            .buttonStyle(PremiumPressButtonStyle())
            .accessibilityLabel(model.isRunning ? "Pause" : "Start")
                Button { model.switchPhase() } label: { Image(systemName: "forward.end.fill").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(WidgetChipStyle(height: 22))
                    .help(model.phase == .work ? "Skip to break" : "Skip to focus")
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var regularBody: some View {
        VStack(spacing: 8) {
            ZStack {
                WidgetRing(progress: model.progress, tint: tint, lineWidth: 5)
                VStack(spacing: 1) {
                    Text(model.timeText)
                        .font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(model.phase.title)
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(tint)
                }
                .padding(8)
            }
            .frame(maxWidth: 104, maxHeight: 104)
            HStack(spacing: 6) {
                Button { model.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(WidgetChipStyle(height: 26)).help("Restart this session")
                playButton(size: 26)
                Button { model.switchPhase() } label: { Image(systemName: "forward.end.fill") }
                    .buttonStyle(WidgetChipStyle(height: 26))
                    .help(model.phase == .work ? "Skip to break" : "Skip to focus")
            }
            if model.completedFocusSessions > 0 {
                Text("\(model.completedFocusSessions) focus session\(model.completedFocusSessions == 1 ? "" : "s") today")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playButton(size: CGFloat) -> some View {
        Button { model.toggle() } label: {
            Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                .frame(minWidth: size - 10)
        }
        .buttonStyle(WidgetChipStyle(prominent: true, height: size))
        .help(model.isRunning ? "Pause" : "Start \(model.phase.title.lowercased())")
        .accessibilityLabel(model.isRunning ? "Pause" : "Start")
    }
}

@MainActor
final class PomodoroModel: ObservableObject {
    static let shared = PomodoroModel()

    enum Phase {
        case work, rest

        var title: String { self == .work ? "Focus" : "Break" }

        @MainActor var duration: TimeInterval {
            TimeInterval((self == .work ? WidgetOptions.shared.focusMinutes : WidgetOptions.shared.breakMinutes) * 60)
        }
    }

    @Published private(set) var phase: Phase = .work
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var isRunning = false
    @Published private(set) var completedFocusSessions = 0
    /// Shortcuts run when a focus session starts and stops, so it can turn a
    /// real Focus mode on and off (macOS has no other way for apps to do that).
    @Published var focusOnShortcut: String = UserDefaults.standard.string(forKey: "focus.onShortcut") ?? "" {
        didSet { UserDefaults.standard.set(focusOnShortcut, forKey: "focus.onShortcut") }
    }
    @Published var focusOffShortcut: String = UserDefaults.standard.string(forKey: "focus.offShortcut") ?? "" {
        didSet { UserDefaults.standard.set(focusOffShortcut, forKey: "focus.offShortcut") }
    }
    private var focusModeOn = false

    private func setFocusMode(_ on: Bool) {
        guard on != focusModeOn else { return }
        let shortcut = on ? focusOnShortcut : focusOffShortcut
        focusModeOn = on
        guard !shortcut.isEmpty else { return }
        AppServices.shared.shortcuts.run(shortcut)
    }

    private var timer: Timer?
    /// When the running phase ends. Remaining time is read from it, so sleep and
    /// late timer callbacks never stretch a session.
    private var deadline: Date?
    private var sessionDay = Calendar.current.startOfDay(for: Date())
    private var optionsObserver: AnyCancellable?

    init() {
        remaining = TimeInterval(WidgetOptions.shared.focusMinutes * 60)
        // A new length applies immediately to a session that hasn't started.
        optionsObserver = WidgetOptions.shared.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                guard let self, !self.isRunning, self.remaining == self.lastDuration else { return }
                self.remaining = self.phase.duration
                self.lastDuration = self.remaining
            }
        }
        lastDuration = remaining
    }

    private var lastDuration: TimeInterval = 0

    var progress: Double {
        let duration = max(phase.duration, 1)
        return 1 - remaining / duration
    }

    var timeText: String {
        let whole = Int(remaining.rounded(.up))
        let minutes = whole / 60
        let seconds = whole % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func toggle() {
        isRunning ? pause() : startTimer()
    }

    private func startTimer() {
        isRunning = true
        if phase == .work { setFocusMode(true) }
        deadline = Date().addingTimeInterval(remaining)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func pause() {
        setFocusMode(false)
        if let deadline { remaining = max(0, deadline.timeIntervalSinceNow) }
        deadline = nil
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let deadline else { return }
        remaining = max(0, deadline.timeIntervalSinceNow)
        if remaining == 0 { phaseFinished() }
    }

    private func phaseFinished() {
        pause()
        NSSound(named: "Glass")?.play()
        if phase == .work {
            let today = Calendar.current.startOfDay(for: Date())
            if today != sessionDay { sessionDay = today; completedFocusSessions = 0 }
            completedFocusSessions += 1
        }
        switchPhase()
    }

    func switchPhase() {
        pause()
        phase = phase == .work ? .rest : .work
        remaining = phase.duration
        lastDuration = remaining
    }

    func reset() {
        pause()
        remaining = phase.duration
        lastDuration = remaining
    }

    func stopForRemoval() {
        pause()
    }

    deinit {
        timer?.invalidate()
    }
}
