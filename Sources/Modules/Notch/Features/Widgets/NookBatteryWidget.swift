import SwiftUI

struct NookBatteryWidget: View {
    @ObservedObject var monitor: PowerSourceMonitor
    @ObservedObject var bluetooth: BluetoothMonitor
    let compact: Bool
    /// Large shows the same, bigger.
    var large = false
    var onDetailsChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showingDetails = false

    private var level: Int? { monitor.hasReading && monitor.hasBattery ? monitor.batteryLevel : nil }
    private var tint: Color { PowerPalette.tint(monitor.state, accent: theme.notch.accent) }
    private var value: String { level.map { "\($0)%" } ?? (monitor.hasReading ? "AC" : "—") }

    var body: some View {
        Button { showingDetails.toggle() } label: {
            Group {
                if monitor.hasReading && !monitor.hasBattery { desktopBody }
                else { batteryBody }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Mac and connected device batteries")
        .accessibilityLabel("Mac battery, \(value), \(BatteryStatusText.line(monitor, now: Date())). Show device batteries.")
        .popover(isPresented: $showingDetails, arrowEdge: .top) {
            BatteryDetailsView(monitor: monitor, bluetooth: bluetooth)
                .onAppear { bluetooth.refreshBatteries() }
        }
        .onChange(of: showingDetails, perform: onDetailsChanged)
        .onDisappear { onDetailsChanged(false) }
    }

    /// Desktop Macs have no internal battery; accessories are the useful reading.
    private var desktopBody: some View {
        let devices = bluetooth.connectedDevices.filter { $0.batteryPercent != nil }
        return VStack(alignment: .leading, spacing: compact ? 4 : 7) {
            if devices.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "powerplug.fill").foregroundStyle(theme.notch.accent)
                    Text("On power").font(.system(size: compact ? 12 : 14, weight: .semibold))
                }
                Text("Connected accessories appear here").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(devices.prefix(compact ? 1 : 3)) { device in
                    HStack(spacing: 7) {
                        Image(systemName: device.systemImage).font(.system(size: 12)).frame(width: 16)
                        Text(device.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        if let level = device.batteryPercent {
                            BatteryGaugeView(level: level, charging: false, tint: level <= 20 ? .orange : theme.notch.accent, width: 20)
                            Text("\(level)%").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every size is the battery itself: the gauge (its bolt shows charging) and the level.
    /// One quiet line appears only when it says something the level doesn't: time to full
    /// while charging, not charging on power, or a warning.
    private var batteryBody: some View {
        let gauge: CGFloat = compact ? 25 : (large ? 64 : 44)
        let size: CGFloat = compact ? 16 : (large ? 44 : 28)
        return VStack(alignment: compact ? .leading : .center, spacing: compact ? 5 : (large ? 12 : 8)) {
            if compact {
                HStack(spacing: 7) {
                    BatteryGaugeView(level: level, charging: monitor.state == .charging, tint: tint, width: gauge)
                    Text(value).font(.system(size: size, weight: .semibold)).monospacedDigit().lineLimit(1)
                }
            } else {
                BatteryGaugeView(level: level, charging: monitor.state == .charging, tint: tint, width: gauge)
                Text(value).font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
                    .foregroundStyle(monitor.state.isWarning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
            }
            if let note {
                Text(note)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(monitor.state.isWarning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            devicesLine
        }
    }

    private var note: String? {
        switch monitor.state {
        // The small tile has room for "Full in 40 min" without "about".
        case .charging: return monitor.minutesToFullShown.map {
            "Full in " + (compact ? BatteryStatusText.fullIn($0).replacingOccurrences(of: "about ", with: "") : BatteryStatusText.fullIn($0))
        }
        case .notCharging, .low, .draining: return BatteryStatusText.word(monitor.state)
        default: return nil
        }
    }

    @ViewBuilder private var devicesLine: some View {
        if !bluetooth.connectedDevices.isEmpty {
            Text("\(bluetooth.connectedDevices.count) device\(bluetooth.connectedDevices.count == 1 ? "" : "s")  ›")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(theme.notch.accent)
        }
    }
}

/// The battery popover: this Mac's state and System Information's health, Low Power
/// Mode, and connected devices. No volts, current, charger or time left.
struct BatteryDetailsView: View {
    @ObservedObject var monitor: PowerSourceMonitor
    @ObservedObject var bluetooth: BluetoothMonitor
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var lowPower = LowPowerMode.shared

    private var tint: Color { PowerPalette.tint(monitor.state, accent: theme.notch.accent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Batteries").font(.system(size: 17, weight: .semibold))
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer").font(.system(size: 22)).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("This Mac").font(.system(size: 12, weight: .semibold))
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(BatteryStatusText.line(monitor, now: context.date)).font(.system(size: 11))
                            .foregroundStyle(monitor.state.isWarning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if monitor.hasReading && monitor.hasBattery {
                    HStack(spacing: 5) {
                        BatteryGaugeView(level: monitor.batteryLevel, charging: monitor.state == .charging, tint: tint, width: 23)
                        Text("\(monitor.batteryLevel)%").font(.system(size: 11, weight: .semibold)).monospacedDigit().fixedSize()
                            .foregroundStyle(monitor.state.isWarning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
                    }
                }
            }
            .help(BatteryStatusText.help(monitor))
            .accessibilityElement(children: .combine)
            if monitor.hasReading && monitor.hasBattery {
                facts
                // Apple's Low Power Mode, the same switch as in System Settings → Battery.
                HStack {
                    Text("Low Power Mode").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Toggle("Low Power Mode", isOn: Binding(get: { lowPower.isEnabled }, set: { lowPower.setEnabled($0) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        .disabled(lowPower.isChanging)
                }
                .help("Lowers energy use for longer battery life. Changing it asks for your password unless the MacSpaces helper is allowed in Login Items.")
            }
            Divider()
            Text("Connected devices").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if bluetooth.connectedDevices.isEmpty {
                Text("No Bluetooth devices connected.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(bluetooth.connectedDevices) { device in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: device.systemImage).font(.system(size: 22)).frame(width: 30, height: 28)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(device.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                    if device.batteryLevels.left != nil || device.batteryLevels.right != nil || device.batteryLevels.caseLevel != nil {
                                        HStack(spacing: 16) {
                                            component("Left", value: device.batteryLevels.left)
                                            component("Right", value: device.batteryLevels.right)
                                            component("Case", value: device.batteryLevels.caseLevel)
                                        }
                                    } else if let level = device.batteryPercent {
                                        batteryValue(level)
                                    } else {
                                        Text("Connected. This device doesn't share its battery level with macOS.")
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 250)
            }
        }
        .padding(20).frame(width: 380)
        .onAppear { monitor.beginDetails() }
        .onDisappear { monitor.endDetails() }
    }

    /// Maximum capacity, cycle count and temperature, each only when macOS reports it.
    @ViewBuilder private var facts: some View {
        let capacity = monitor.health?.maximumCapacity
        let condition = monitor.health?.conditionNormal
        let temperature = monitor.temperatureC.map {
            Measurement(value: Double($0), unit: UnitTemperature.celsius)
                .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
        if capacity != nil || monitor.cycleCount != nil || temperature != nil {
            HStack(alignment: .top, spacing: 8) {
                if let capacity {
                    fact("Maximum capacity", "\(capacity)%",
                         note: condition.map { $0 ? "Normal" : "Service recommended" }, noteIsWarning: condition == false,
                         help: "Maximum capacity and condition as System Information reports them.")
                }
                if let cycles = monitor.cycleCount {
                    fact("Cycle count", "\(cycles)", help: "Full charge cycles so far, as macOS counts them.")
                }
                if let temperature {
                    fact("Temperature", temperature, help: "The battery's temperature.")
                }
            }
        }
    }

    private func fact(_ title: String, _ value: String, note: String? = nil, noteIsWarning: Bool = false, help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
            if let note {
                Text(note).font(.system(size: 10))
                    .foregroundStyle(noteIsWarning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .help(help)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func component(_ title: String, value: Int?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                batteryValue(value)
            }
        }
    }

    private func batteryValue(_ level: Int) -> some View {
        HStack(spacing: 5) {
            BatteryGaugeView(level: level, charging: false, tint: level <= 20 ? .orange : theme.notch.accent, width: 23)
            Text("\(level)%").font(.system(size: 11, weight: .semibold)).monospacedDigit().fixedSize()
                .foregroundStyle(level <= 20 ? Color.orange : .primary)
        }
    }
}
