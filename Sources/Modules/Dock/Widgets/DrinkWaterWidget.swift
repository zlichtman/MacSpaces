import SwiftUI
import AppKit

/// Hydration tracker: tap to log a glass; the count resets daily and a gentle
/// sound reminds you every interval while below the goal.
struct DrinkWaterWidget: View {
    @StateObject private var model = DrinkWaterModel()

    var body: some View {
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                model.undo()
            } else {
                model.logGlass()
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: model.count >= model.goal ? "drop.fill" : "drop")
                    .font(.system(size: 16))
                    .foregroundStyle(.cyan)
                Text("\(model.count)/\(model.goal)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("glasses")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { model.reset() }
        )
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .help("Click to log water, Option-click to undo, double-click to reset")
    }
}

@MainActor
private final class DrinkWaterModel: ObservableObject {
    @Published private(set) var count: Int = 0
    let goal = 8

    private let countKey = "drinkWaterCount"
    private let dayKey = "drinkWaterDay"
    private var reminderTimer: Timer?

    init() {
        rollOverDayIfNeeded()
        count = UserDefaults.standard.integer(forKey: countKey)
    }

    func start() {
        guard reminderTimer == nil else { return }
        // Gentle chime every 45 minutes while below goal.
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 45 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rollOverDayIfNeeded()
                if self.count < self.goal {
                    NSSound(named: "Ping")?.play()
                }
            }
        }
    }

    func stop() {
        reminderTimer?.invalidate()
        reminderTimer = nil
    }

    deinit {
        reminderTimer?.invalidate()
    }

    func logGlass() {
        rollOverDayIfNeeded()
        count += 1
        persist()
    }

    func undo() {
        count = max(0, count - 1)
        persist()
    }

    func reset() {
        count = 0
        persist()
    }

    private func rollOverDayIfNeeded() {
        let today = ISO8601DateFormatter.dayString(from: Date())
        let stored = UserDefaults.standard.string(forKey: dayKey)
        if stored != today {
            UserDefaults.standard.set(today, forKey: dayKey)
            UserDefaults.standard.set(0, forKey: countKey)
            count = 0
        }
    }

    private func persist() {
        UserDefaults.standard.set(count, forKey: countKey)
    }
}

private extension ISO8601DateFormatter {
    static func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
