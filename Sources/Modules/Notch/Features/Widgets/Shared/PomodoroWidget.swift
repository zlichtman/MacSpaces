import SwiftUI
import AppKit

/// Classic 25/5 pomodoro timer with a progress ring. Click to start/pause,
/// right-click to reset or switch phase.
struct PomodoroWidget: View {
    var compact = false
    @StateObject private var model = PomodoroModel()

    var body: some View {
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                model.switchPhase()
            } else {
                model.toggle()
            }
        } label: {
            if compact {
                HStack(spacing: 8) {
                    compactRing
                        .frame(width: 23, height: 23)
                    Text(model.timeText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 2)
                }
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            } else {
                timerRing
                    .padding(12)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { model.reset() }
        )
        .help("Click to start or pause, double-click to reset, Option-click to switch phase")
        .onDisappear { model.stopForRemoval() }
    }

    private var timerRing: some View {
        ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: model.progress)
                    .stroke(model.phase == .work ? Color.red : Color.green,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: model.progress)

                VStack(spacing: 0) {
                    Text(model.timeText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
            }
    }

    private var compactRing: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(
                    model.phase == .work ? Color.red : Color.green,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: model.progress)
        }
    }
}

@MainActor
final class PomodoroModel: ObservableObject {
    enum Phase {
        case work, rest

        var duration: TimeInterval {
            self == .work ? 25 * 60 : 5 * 60
        }
    }

    @Published private(set) var phase: Phase = .work
    @Published private(set) var remaining: TimeInterval = Phase.work.duration
    @Published private(set) var isRunning = false

    private var timer: Timer?

    var progress: CGFloat {
        1 - CGFloat(remaining / phase.duration)
    }

    var timeText: String {
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func toggle() {
        isRunning ? pause() : startTimer()
    }

    private func startTimer() {
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard remaining > 0 else {
            phaseFinished()
            return
        }
        remaining -= 1
    }

    private func phaseFinished() {
        pause()
        NSSound(named: "Glass")?.play()
        switchPhase()
    }

    func switchPhase() {
        pause()
        phase = phase == .work ? .rest : .work
        remaining = phase.duration
    }

    func reset() {
        pause()
        remaining = phase.duration
    }

    func stopForRemoval() {
        pause()
    }

    deinit {
        timer?.invalidate()
    }
}
