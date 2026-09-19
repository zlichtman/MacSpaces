import SwiftUI

struct SystemStatsWidget: View {
    @ObservedObject var service: SystemStatsService
    @ObservedObject private var theme = ThemeStore.shared
    let isVertical: Bool
    @State private var showingDetails = false

    var body: some View {
        Button {
            showingDetails.toggle()
        } label: {
            HStack(spacing: isVertical ? 8 : 16) {
                StatRing(label: "CPU", value: service.cpuUsage, tint: .blue, compact: isVertical)
                StatRing(label: "MEM", value: service.memoryUsage, tint: .purple, compact: isVertical)

                if let battery = service.batteryLevel {
                    StatRing(label: service.isCharging ? "⚡︎" : "BAT",
                             value: Double(battery) / 100,
                             tint: battery <= 20 ? .red : theme.dock.accent,
                             compact: isVertical)
                } else {
                    StatRing(
                        label: "DSK",
                        value: service.diskUsage,
                        tint: theme.dock.accent,
                        compact: isVertical
                    )
                }
            }
            .padding(.horizontal, isVertical ? 6 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDetails, arrowEdge: .top) {
            details
        }
        .help("Open system details")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("System")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Live")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.dock.accent)
            }

            SystemMetricRow(
                title: "CPU",
                symbol: "cpu",
                value: service.cpuUsage,
                tint: .blue
            )
            SystemMetricRow(
                title: "Memory",
                symbol: "memorychip",
                value: service.memoryUsage,
                tint: .purple
            )
            SystemMetricRow(
                title: "Disk",
                symbol: "internaldrive",
                value: service.diskUsage,
                tint: theme.dock.accent
            )
            if let battery = service.batteryLevel {
                SystemMetricRow(
                    title: service.isCharging ? "Battery · Charging" : "Battery",
                    symbol: service.isCharging ? "bolt.fill" : "battery.50percent",
                    value: Double(battery) / 100,
                    tint: battery <= 20 ? .red : .green
                )
            }
        }
        .padding(14)
        .frame(width: 270)
    }
}

private struct SystemMetricRow: View {
    let title: String
    let symbol: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(Int((value * 100).rounded()))%")
                        .monospacedDigit()
                }
                .font(.system(size: 11, weight: .medium))

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.1))
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * max(0.01, value))
                    }
                }
                .frame(height: 4)
            }
        }
    }
}

private struct StatRing: View {
    let label: String
    let value: Double
    let tint: Color
    let compact: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.02, value))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: value)
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: compact ? 8 : 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)

            Text(label)
                .font(.system(size: compact ? 7 : 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}
