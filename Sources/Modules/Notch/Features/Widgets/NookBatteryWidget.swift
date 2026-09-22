import SwiftUI

struct NookBatteryWidget: View {
    @ObservedObject var monitor: PowerSourceMonitor
    @ObservedObject var bluetooth: BluetoothMonitor
    let compact: Bool
    var onDetailsChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showingDetails = false

    private var level: Int? { monitor.hasReading && monitor.hasBattery ? monitor.batteryLevel : nil }
    private var tint: Color { level.map { $0 <= 20 && !monitor.isOnExternalPower } == true ? .orange : theme.notch.accent }
    private var value: String { level.map { "\($0)%" } ?? (monitor.hasReading ? "AC" : "—") }

    var body: some View {
        Button { showingDetails.toggle() } label: {
            VStack(alignment: compact ? .leading : .center, spacing: compact ? 5 : 9) {
                if compact {
                    HStack(spacing: 7) {
                        BatteryGaugeView(level: level, charging: monitor.isCharging, tint: tint, width: 25)
                        Text(value).font(.system(size: 16, weight: .semibold)).monospacedDigit().lineLimit(1)
                    }
                } else {
                    BatteryGaugeView(level: level, charging: monitor.isCharging, tint: tint, width: 44)
                    Text(value).font(.system(size: 25, weight: .semibold)).monospacedDigit().lineLimit(1)
                }
                Text(monitor.statusLabel).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                if !bluetooth.connectedDevices.isEmpty {
                    Text("\(bluetooth.connectedDevices.count) devices  ›")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(theme.notch.accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Mac and connected device batteries")
        .accessibilityLabel("Mac battery, \(value), \(monitor.statusLabel). Show device batteries.")
        .popover(isPresented: $showingDetails, arrowEdge: .top) {
            BatteryDetailsView(monitor: monitor, bluetooth: bluetooth)
                .onAppear { bluetooth.refreshBatteries() }
        }
        .onChange(of: showingDetails, perform: onDetailsChanged)
        .onDisappear { onDetailsChanged(false) }
    }
}

struct BatteryDetailsView: View {
    @ObservedObject var monitor: PowerSourceMonitor
    @ObservedObject var bluetooth: BluetoothMonitor
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Batteries").font(.system(size: 17, weight: .semibold))
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer").font(.system(size: 22)).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("This Mac").font(.system(size: 12, weight: .semibold))
                    Text(monitor.statusLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if monitor.hasReading && monitor.hasBattery {
                    batteryValue(monitor.batteryLevel, charging: monitor.isCharging)
                }
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
                                        Text("Battery not reported by macOS").font(.system(size: 11)).foregroundStyle(.secondary)
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
    }

    @ViewBuilder private func component(_ title: String, value: Int?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                batteryValue(value)
            }
        }
    }

    private func batteryValue(_ level: Int, charging: Bool = false) -> some View {
        HStack(spacing: 5) {
            BatteryGaugeView(level: level, charging: charging, tint: level <= 20 ? .orange : theme.notch.accent, width: 23)
            Text("\(level)%").font(.system(size: 11, weight: .semibold)).monospacedDigit().fixedSize()
                .foregroundStyle(level <= 20 && !charging ? Color.orange : .primary)
        }
    }
}
