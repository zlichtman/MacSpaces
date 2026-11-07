import SwiftUI

/// One colour rule for every power view: orange for low battery or a confirmed drain
/// on power, the theme's accent otherwise.
enum PowerPalette {
    static func tint(_ state: BatteryState, accent: Color) -> Color { state.isWarning ? .orange : accent }

    /// The notice beside the notch: orange for a low or draining notice, or while the
    /// state is a warning.
    @MainActor static func noticeTint(_ monitor: PowerSourceMonitor, accent: Color) -> Color {
        let kind = monitor.notice?.kind
        return kind == .low || kind == .draining || monitor.state.isWarning ? .orange : accent
    }
}

/// The battery's words, shared by the Overtime row, the Battery widget, its popover and
/// the notice beside the notch. Every figure is macOS's own; nothing here is estimated.
enum BatteryStatusText {
    static let sourcesNote = "Maximum capacity and condition as System Information reports them. Time to full is macOS's own estimate."

    /// "under 5 min", "about 25 min", "about 1 h 20 min", "more than 10 h".
    static func fullIn(_ minutes: Int) -> String {
        if minutes < 5 { return "under 5 min" }
        if minutes >= 600 { return "more than 10 h" }
        let step = minutes < 60 ? 5.0 : 10.0
        return "about " + duration(Int((Double(minutes) / step).rounded() * step))
    }

    /// Time since unplugging: "for 12 min", "for 1 h 20 min" (minutes floored to 5).
    static func onBatteryFor(since: Date?, now: Date) -> String? {
        guard let since else { return nil }
        let minutes = Int(now.timeIntervalSince(since) / 60)
        guard minutes >= 1 else { return nil }
        return "for " + duration(minutes < 60 ? minutes : minutes / 5 * 5)
    }

    /// A time for the battery pill, rounded so it reads at a glance: "35 min",
    /// "5 h 20 min", "10+ h". It's macOS's estimate, so it never claims the minute.
    static func span(_ minutes: Int) -> String {
        if minutes < 5 { return "5 min" }
        if minutes >= 600 { return "10+ h" }
        let step = minutes < 60 ? 5.0 : 10.0
        return duration(Int((Double(minutes) / step).rounded() * step))
    }

    private static func duration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// The short form, for the Small and Medium widgets and VoiceOver.
    static func word(_ state: BatteryState) -> String {
        switch state {
        case .charging: return "Charging"
        case .fullyCharged: return "Fully charged"
        case .notCharging: return "Not charging"
        case .onBattery: return "On battery"
        case .low: return "Low battery"
        case .draining: return "Draining on power"
        case .unavailable: return "Battery unavailable"
        case .noBattery: return "On power"
        }
    }

    /// The long form, for the Battery row, the Large widget and the popover.
    static func line(_ state: BatteryState, minutesToFull: Int?, since: Date?, now: Date) -> String {
        switch state {
        case .charging: return minutesToFull.map { "Charging · full in " + fullIn($0) } ?? "Charging"
        case .onBattery: return onBatteryFor(since: since, now: now).map { "On battery " + $0 } ?? "On battery"
        default: return word(state)
        }
    }

    @MainActor static func line(_ monitor: PowerSourceMonitor, now: Date) -> String {
        line(monitor.state, minutesToFull: monitor.minutesToFullShown, since: monitor.onBatterySince, now: now)
    }

    /// "Maximum capacity 87% · 343 cycles", or "Maximum capacity 76% · service
    /// recommended"; nil until System Information has been read, or with nothing to say.
    static func healthLine(_ health: BatteryHealth?, cycles: Int?) -> String? {
        healthParts(health, cycles: cycles).map { $0.text + ($0.service ?? "") }
    }

    /// The health line with only "service recommended" in orange.
    static func healthText(_ health: BatteryHealth?, cycles: Int?) -> Text? {
        healthParts(health, cycles: cycles).map { parts in
            parts.service.map { Text(parts.text) + Text($0).foregroundColor(.orange) } ?? Text(parts.text)
        }
    }

    private static func healthParts(_ health: BatteryHealth?, cycles: Int?) -> (text: String, service: String?)? {
        guard let health else { return nil }
        let service = health.conditionNormal == false
        var parts: [String] = []
        if let capacity = health.maximumCapacity { parts.append("Maximum capacity \(capacity)%") }
        if !service, let cycles { parts.append("\(cycles) cycles") }
        let text = parts.joined(separator: " · ")
        guard service else { return text.isEmpty ? nil : (text, nil) }
        return text.isEmpty ? ("", "Service recommended") : (text + " · ", "service recommended")
    }

    /// What the state means, then where the figures come from.
    static func help(_ state: BatteryState, drainFrom: Int?, level: Int, chargerWatts: Int?) -> String {
        let lead: String?
        switch state {
        case .notCharging:
            lead = "Plugged in, but macOS isn't charging the battery right now. Optimized Charging, a charge limit or a warm battery can hold it."
        case .draining:
            let charger = chargerWatts.map { "\($0) W charger" } ?? "charger"
            lead = "Plugged in, but the battery fell from \(drainFrom.map { "\($0)%" } ?? "its peak") to \(level)% while the \(charger) gave all it can. Use a stronger charger or plug straight into the Mac."
        case .onBattery:
            lead = "Time since you unplugged, including sleep."
        default:
            lead = nil
        }
        return [lead, sourcesNote].compactMap { $0 }.joined(separator: " ")
    }

    @MainActor static func help(_ monitor: PowerSourceMonitor) -> String {
        help(monitor.state, drainFrom: monitor.drainFromLevel, level: monitor.batteryLevel, chargerWatts: monitor.charger?.connectionWatts)
    }

    /// "Battery, 87%, charging, full in about 40 min. Maximum capacity 87%, 343 cycles."
    @MainActor static func accessibilityLabel(_ monitor: PowerSourceMonitor) -> String {
        let status = line(monitor, now: Date()).replacingOccurrences(of: " · ", with: ", ").lowercased()
        let health = healthLine(monitor.health, cycles: monitor.cycleCount).map { " " + $0.replacingOccurrences(of: " · ", with: ", ") + "." } ?? ""
        return "Battery, \(monitor.batteryLevel)%, \(status).\(health)"
    }
}

/// The power column: whether the charger keeps up (a plain thumbs up or down), Low
/// Power Mode, the battery's health, and other devices' batteries in one row, as rows
/// that line up with Overtime's. Watts and the charger's name stay in the verdict's help.
struct CableManagementCard: View {
    @ObservedObject var power: PowerSourceMonitor
    @ObservedObject var input: PowerInputSampler
    @ObservedObject var bluetooth: BluetoothMonitor
    var compact = false
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var lowPower = LowPowerMode.shared

    private var pluggedIn: Bool {
        // With no battery reading the state can't say; macOS's power source still can.
        power.state.isOnAC || (power.state == .unavailable && power.isOnExternalPower)
    }

    private var devices: [BluetoothDeviceSnapshot] {
        bluetooth.connectedDevices.filter { $0.batteryPercent != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            verdict
            if power.hasBattery {
                Divider().opacity(0.5)
                PowerRow(symbol: lowPower.isEnabled ? "leaf.fill" : "leaf", title: "Low Power Mode",
                         detail: lowPower.isEnabled ? "On: saving energy" : "Off: full performance", active: lowPower.isEnabled, compact: compact) {
                    Toggle("Low Power Mode", isOn: Binding(get: { lowPower.isEnabled }, set: { lowPower.setEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .disabled(lowPower.isChanging)
                }
                .help("Lowers energy use for longer battery life. Changing it asks for your password unless the MacSpaces helper is allowed in Login Items.")
                Divider().opacity(0.5)
                let health = healthDetail
                PowerRow(symbol: "heart", title: "Battery health", detail: health?.text ?? "Reading battery health…",
                         detailTint: health?.service == true ? .orange : nil, active: false, compact: compact) { EmptyView() }
                    .help(BatteryStatusText.sourcesNote)
            }
            if !compact, let first = devices.first {
                // Every device in one row: "AirPods Pro 80% · Magic Mouse 45%".
                Divider().opacity(0.5)
                PowerRow(symbol: first.systemImage, title: devices.count == 1 ? first.name : "Devices",
                         detail: devices.count == 1 ? first.batteryPercent.map { "\($0)%" }
                             : devices.map { "\($0.name) \($0.batteryPercent ?? 0)%" }.joined(separator: " · "),
                         detailTint: devices.contains { ($0.batteryPercent ?? 100) <= 20 } ? .orange : nil, active: false, compact: compact) { EmptyView() }
                    .help(devices.map { "\($0.name): \($0.batteryPercent ?? 0)%" }.joined(separator: "\n"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 8)
        .onAppear { input.retain(); bluetooth.refreshBatteries() }
        .onDisappear { input.release() }
    }

    // MARK: Verdict

    private struct Verdict { let symbol: String; let title: String; let detail: String; let warning: Bool; let active: Bool }

    private var verdict: some View {
        let v = verdictValue
        return TimelineView(.periodic(from: .now, by: 60)) { _ in
            PowerRow(symbol: v.symbol, title: v.title, detail: verdictValue.detail,
                     detailTint: v.warning ? .orange : nil, symbolTint: v.warning ? .orange : nil, active: v.active, compact: compact) { EmptyView() }
        }
        .help(verdictHelp)
    }

    private var verdictValue: Verdict {
        if power.state == .noBattery {
            return Verdict(symbol: "powerplug.fill", title: "On power", detail: "Built-in power supply", warning: false, active: true)
        }
        guard pluggedIn else {
            let since = BatteryStatusText.onBatteryFor(since: power.onBatterySince, now: Date())
            return Verdict(symbol: "powerplug", title: "Not plugged in", detail: since.map { "On battery " + $0 } ?? "On battery",
                           warning: false, active: false)
        }
        switch power.state {
        case .draining:
            return Verdict(symbol: "hand.thumbsdown.fill", title: "Falling behind", detail: "Using more than it gives",
                           warning: true, active: true)
        case .charging:
            return Verdict(symbol: "hand.thumbsup.fill", title: "Keeping up",
                           detail: input.atLimit ? "Charging, with nothing spare" : "Charging while you work",
                           warning: false, active: true)
        case .fullyCharged:
            return Verdict(symbol: "hand.thumbsup.fill", title: "Keeping up", detail: "Full, running on power", warning: false, active: true)
        case .notCharging:
            return Verdict(symbol: "hand.thumbsup.fill", title: "Keeping up", detail: "Running on power", warning: false, active: true)
        default:
            return Verdict(symbol: "powerplug.fill", title: "Plugged in", detail: "Reading the battery…", warning: false, active: true)
        }
    }

    /// The charger itself, for anyone who wants it: its name, what it can give here,
    /// and whether something on the way limits it.
    private var verdictHelp: String {
        guard pluggedIn, let charger = power.charger else {
            return power.lastCharger.map { "Last charger: \($0.name)." } ?? "Shows whether your charger keeps up once you plug in."
        }
        var parts = [charger.name + (charger.connectionWatts.map { ", giving up to \($0) W here" } ?? "") + "."]
        if let rated = charger.ratedWatts, let connection = charger.connectionWatts, rated >= connection + 10 {
            parts.append("This \(rated) W charger is limited to \(connection) W by the cable, a hub or the port.")
        }
        if power.state == .draining { parts.append("Use a stronger charger, or plug straight into the Mac.") }
        if let watts = input.shownWatts { parts.append("Coming in now: \(watts) W.") }
        return parts.joined(separator: " ")
    }

    private var healthDetail: (text: String, service: Bool)? {
        guard let health = power.health else { return nil }
        let service = health.conditionNormal == false
        if service { return ("Service recommended", true) }
        var parts: [String] = []
        if let capacity = health.maximumCapacity { parts.append("\(capacity)% capacity") }
        if let cycles = power.cycleCount { parts.append("\(cycles) cycles") }
        return parts.isEmpty ? nil : (parts.joined(separator: " · "), false)
    }
}

/// One row of the power column, with the same metrics as Overtime's rows so the two
/// columns line up: a 30 pt icon, a title and one line, and a trailing control.
struct PowerRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String?
    var detailTint: Color? = nil
    var symbolTint: Color? = nil
    let active: Bool
    var compact = false
    @ViewBuilder let trailing: Trailing
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? AnyShapeStyle(symbolTint ?? theme.notch.accent) : AnyShapeStyle(.secondary))
                .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                .background(active ? (symbolTint ?? theme.notch.accent).opacity(0.14) : Color.primary.opacity(0.06), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let detail {
                    Text(detail).font(.system(size: compact ? 10 : 11))
                        .foregroundStyle(detailTint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.vertical, compact ? 4 : 6)
        .frame(height: compact ? 64 : nil)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
