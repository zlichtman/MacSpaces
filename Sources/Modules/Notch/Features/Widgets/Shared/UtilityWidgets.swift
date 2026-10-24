import SwiftUI

/// One tap keeps the Mac awake; the chips choose how long before starting.
struct KeepAwakeWidget: View {
    @ObservedObject var service: KeepAwakeService
    var compact = false
    @ObservedObject private var theme = ThemeStore.shared
    @State private var minutes = 60
    @State private var displayToo = false

    private static let durations: [(label: String, minutes: Int)] = [("15m", 15), ("1h", 60), ("2h", 120), ("∞", 0)]

    var body: some View {
        if compact {
            HStack(spacing: 8) {
                toggleButton(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(service.isActive ? "Awake" : "Sleep allowed")
                        .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    statusText.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 9) {
                toggleButton(size: 48)
                VStack(spacing: 2) {
                    Text(service.isActive ? (displayToo ? "Mac and display awake" : "Mac awake") : "Sleep allowed")
                        .font(.system(size: 12, weight: .semibold))
                    statusText.font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                }
                if !service.isActive {
                    HStack(spacing: 5) {
                        ForEach(Self.durations, id: \.minutes) { option in
                            Button(option.label) { minutes = option.minutes }
                                .buttonStyle(WidgetChipStyle(prominent: minutes == option.minutes, height: 22))
                                .help(option.minutes == 0 ? "Until you stop it" : "For \(option.label)")
                        }
                    }
                    Toggle("Keep display on", isOn: $displayToo)
                        .toggleStyle(.checkbox).controlSize(.small).font(.system(size: 10))
                }
                if let error = service.error {
                    Text(error).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func toggleButton(size: CGFloat) -> some View {
        Button {
            if service.isActive { service.stop() }
            else { service.start(mode: displayToo ? .display : .system, minutes: minutes == 0 ? nil : minutes) }
        } label: {
            Image(systemName: service.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(service.isActive ? Color.black.opacity(0.82) : Color.primary)
                .frame(width: size, height: size)
                .background(service.isActive ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(Color.primary.opacity(0.09)),
                            in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .help(service.isActive ? "Allow sleep" : "Keep awake")
        .accessibilityLabel(service.isActive ? "Allow sleep" : "Keep Mac awake")
    }

    @ViewBuilder
    private var statusText: some View {
        if let end = service.expiresAt {
            Text(end, style: .timer)
        } else if service.isActive {
            Text("Until you stop it")
        } else {
            Text(minutes == 0 ? "Tap to stay awake" : "Tap for \(Self.durations.first { $0.minutes == minutes }?.label ?? "")")
        }
    }
}

struct SystemStatsWidget: View {
    @ObservedObject var service: SystemStatsService
    var compact = false
    /// The System page: CPU, memory and network graphs beside a grid of details.
    var detailed = false
    var horizontal = false
    var power: PowerSourceMonitor? = nil
    var bluetooth: BluetoothMonitor? = nil
    var onBatteryDetailsChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        if detailed && horizontal {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        ring("CPU", service.cpuUsage)
                        ring("Memory", service.memoryUsage)
                        ring("Disk", service.diskUsage)
                        if let power {
                            SystemBatteryRing(power: power, bluetooth: bluetooth, compact: true, onDetailsChanged: onBatteryDetailsChanged)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("↓ " + rate(service.networkInRate)).foregroundStyle(theme.notch.accent)
                        Text("↑ " + rate(service.networkOutRate)).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 9, weight: .medium)).monospacedDigit().lineLimit(1)
                }
                .frame(width: 156)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .topLeading), count: 3),
                          alignment: .leading, spacing: 9) {
                    detail("Memory", bytes(service.memoryUsedBytes))
                    detail("Swap", service.swapUsedBytes > 0 ? bytes(service.swapUsedBytes) : "None")
                    detail("Disk", storage(service.diskFreeBytes)).help("Free disk space: " + bytes(service.diskFreeBytes))
                    detail("Load", String(format: "%.2f", service.loadAverage))
                    detail("Up", uptime(service.uptime))
                    detail("Thermal", thermal(service.thermalState), warn: service.thermalState == .serious || service.thermalState == .critical)
                }
                history.frame(width: 120)
            }
        } else if detailed {
            // Built for the System page's narrow card: rings across the top, details in a
            // grid, and the last three minutes as one graph across the bottom.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ring("CPU", service.cpuUsage)
                    ring("Memory", service.memoryUsage)
                    ring("Disk", service.diskUsage)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NETWORK").font(.system(size: 8, weight: .bold)).tracking(0.3).foregroundStyle(.secondary)
                        Text("↓ " + rate(service.networkInRate)).foregroundStyle(theme.notch.accent)
                        Text("↑ " + rate(service.networkOutRate)).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .topLeading), count: 3),
                          alignment: .leading, spacing: 9) {
                    detail("Memory", bytes(service.memoryUsedBytes))
                    detail("Swap", service.swapUsedBytes > 0 ? bytes(service.swapUsedBytes) : "None")
                    detail("Disk", storage(service.diskFreeBytes)).help("Free disk space: " + bytes(service.diskFreeBytes))
                    detail("Load", String(format: "%.2f", service.loadAverage))
                    detail("Up", uptime(service.uptime))
                    detail("Thermal", thermal(service.thermalState), warn: service.thermalState == .serious || service.thermalState == .critical)
                }
                Spacer(minLength: 0)
                history
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 9)
            .frame(maxHeight: .infinity, alignment: .top)
        } else if compact {
            HStack(spacing: 0) {
                gauge("CPU", service.cpuUsage)
                gauge("MEM", service.memoryUsage)
                gauge("DISK", service.diskUsage)
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                metric("CPU", value: service.cpuUsage, values: service.history.map(\.cpu))
                metric("Memory", value: service.memoryUsage, values: service.history.map(\.memory))
                metric("Disk", value: service.diskUsage, values: service.history.map(\.disk))
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 9)
            .frame(maxHeight: .infinity)
            .help("Last 3 minutes, sampled every 3 seconds")
        }
    }

    private func tint(for value: Double) -> Color {
        value >= 0.9 ? .red : value >= 0.75 ? .orange : theme.notch.accent
    }

    private func gauge(_ name: String, _ value: Double) -> some View {
        VStack(spacing: 3) {
            ZStack {
                WidgetRing(progress: value, tint: tint(for: value), lineWidth: 3)
                Text("\(Int(value * 100))").font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(width: 30, height: 30)
            Text(name).font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(Int(value * 100)) percent")
    }

    private func ring(_ name: String, _ value: Double) -> some View {
        SystemMetricRing(name: name, value: value, tint: tint(for: value), compact: horizontal)
    }

    /// CPU and memory over the last three minutes, one line each, full width.
    private var history: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: horizontal ? 4 : 10) {
                legend("CPU", tint(for: service.cpuUsage))
                legend("Memory", theme.nookForeground.opacity(0.55))
                Spacer(minLength: 0)
                Text(horizontal ? "3m" : "Last 3 min").font(.system(size: 8, weight: .medium)).foregroundStyle(.tertiary)
            }
            ZStack {
                Sparkline(values: series(\.memory), tint: theme.nookForeground.opacity(0.55))
                Sparkline(values: series(\.cpu), tint: tint(for: service.cpuUsage))
            }
            .frame(height: 30)
            .accessibilityHidden(true)
        }
    }

    private func series(_ value: KeyPath<SystemStatsService.Sample, Double>) -> [Double] {
        let values = service.history.map { $0[keyPath: value] }
        return values.count > 1 ? values : [values.first ?? 0, values.first ?? 0]
    }

    private func legend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 10, height: 3)
            Text(name.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.3).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
        }
    }

    private func detail(_ name: String, _ value: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.3).foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(warn ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    /// Storage capacity needs a readable summary; exact free bytes remain in help.
    private func storage(_ value: Double) -> String {
        let units: [(Double, String)] = [(pow(1024, 4), "TB"), (pow(1024, 3), "GB"),
                                         (pow(1024, 2), "MB"), (1024, "KB")]
        guard let unit = units.first(where: { value >= $0.0 }) else { return bytes(value) }
        return (value / unit.0).formatted(.number.precision(.fractionLength(1))) + " " + unit.1
    }

    private func rate(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) + "/s"
    }

    private func uptime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60, hours = minutes / 60, days = hours / 24
        return days > 0 ? "\(days)d \(hours % 24)h" : hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private func metric(_ name: String, value: Double, values: [Double]) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(name).font(.system(size: 10, weight: .medium))
                Spacer()
                Text("\(Int(value * 100))%").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(tint(for: value))
            }
            Sparkline(values: values.isEmpty ? [value, value] : values, tint: tint(for: value))
                .frame(height: 18)
                .accessibilityHidden(true)
        }
    }
}

/// Filled line chart with a baseline, so a short history still reads as data.
private struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = values.enumerated().map { index, sample in
                CGPoint(x: CGFloat(index) / CGFloat(max(1, values.count - 1)) * proxy.size.width,
                        y: (1 - min(1, max(0, sample))) * proxy.size.height)
            }
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}


/// The System page uses the same geometry for every ring.
private struct SystemMetricRing: View {
    let name: String
    let value: Double?
    let tint: Color
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 3 : 4) {
            ZStack {
                WidgetRing(progress: value ?? 0, tint: tint, lineWidth: compact ? 3 : 3.5)
                Text(value.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                    .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
            Text(name.uppercased()).font(.system(size: compact ? 7 : 8, weight: .bold)).tracking(0.3)
                .foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(name) \(Int(($0 * 100).rounded())) percent" } ?? "\(name) unavailable")
    }
}

struct SystemBatteryRing: View {
    @ObservedObject var power: PowerSourceMonitor
    var bluetooth: BluetoothMonitor? = nil
    var compact = false
    var onDetailsChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showingDetails = false

    var body: some View {
        Button { if bluetooth != nil { showingDetails = true } } label: {
            SystemMetricRing(name: "Battery", value: power.hasReading && power.hasBattery ? Double(power.batteryLevel) / 100 : nil,
                tint: PowerPalette.tint(power.state, accent: theme.notch.accent), compact: compact)
        }
        .buttonStyle(.plain)
        .help(BatteryStatusText.help(power))
        .popover(isPresented: $showingDetails, arrowEdge: .top) {
            if let bluetooth { BatteryDetailsView(monitor: power, bluetooth: bluetooth) }
        }
        .onChange(of: showingDetails, perform: onDetailsChanged)
        .onDisappear { onDetailsChanged(false) }
    }
}
