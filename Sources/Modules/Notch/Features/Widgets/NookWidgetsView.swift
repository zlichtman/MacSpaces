import SwiftUI

/// The Widgets tab: at-a-glance tiles (clock, date, battery) plus quick timers.
struct NookWidgetsView: View {
    @ObservedObject var powerMonitor: PowerSourceMonitor
    @ObservedObject var timerService: TimerService

    var body: some View {
        HStack(spacing: 10) {
            clockTile
            dateTile
            if powerMonitor.hasBattery {
                batteryTile
            }
            timerTile
        }
    }

    private var clockTile: some View {
        WidgetTile {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 2) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(context.date, format: .dateTime.second())
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var dateTile: some View {
        WidgetTile {
            VStack(spacing: 2) {
                Text(Date(), format: .dateTime.weekday(.wide))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(Date(), format: .dateTime.day())
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(Date(), format: .dateTime.month(.abbreviated))
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
    }

    private var batteryTile: some View {
        WidgetTile {
            VStack(spacing: 4) {
                Image(systemName: powerMonitor.isCharging ? "bolt.fill" : "battery.100percent")
                    .font(.system(size: 16))
                    .foregroundStyle(powerMonitor.isCharging ? .green : .primary)
                Text("\(powerMonitor.batteryLevel)%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(powerMonitor.isCharging ? "Charging" : "Battery")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timerTile: some View {
        WidgetTile {
            if timerService.isRunning {
                VStack(spacing: 5) {
                    Text(timerService.remainingText)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    ProgressView(value: timerService.progress)
                        .progressViewStyle(.linear)
                        .tint(.orange)
                        .frame(width: 64)
                    Button("Cancel") { timerService.cancel() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 5) {
                    Label("Timer", systemImage: "timer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        ForEach([5, 10, 25], id: \.self) { minutes in
                            Button("\(minutes)m") {
                                timerService.start(minutes: minutes)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

private struct WidgetTile<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
