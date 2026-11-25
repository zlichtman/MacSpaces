import AppKit
import Combine
import CoreAudio

/// The Status icon: a second menu-bar icon that stands in for several of the system's own. All
/// in One draws the battery as a ring, Wi-Fi in its middle and the volume as a bar beside it; or
/// the ring can be one reading (battery, CPU, memory, disk or network). Everything is in its
/// menu, with the sound outputs to switch between. Off for everyone until its switch is turned
/// on; while it's off there is no icon, no observer and nothing is sampled for it. It reads what
/// the System page already reads (`SystemStatsService`, `PowerSourceMonitor`) plus Wi-Fi's state
/// and the output volume (`StatusSignals`), asks for nothing and contacts nothing.
@MainActor
final class StatusIconFeature: ObservableObject {
    static let shared = StatusIconFeature()

    @Published private(set) var isOn: Bool
    /// The reading the ring shows.
    @Published var reading: StatusReading {
        didSet { UserDefaults.standard.set(reading.rawValue, forKey: WidgetOptions.Keys.statusIconReading); item?.refresh() }
    }
    /// Its number beside the ring.
    @Published var showsValue: Bool {
        didSet { UserDefaults.standard.set(showsValue, forKey: WidgetOptions.Keys.statusIconShowsValue); item?.refresh() }
    }

    /// How big the icon is drawn.
    enum Size: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var points: CGFloat { switch self { case .small: return 15; case .medium: return 18; case .large: return 21 } }
    }
    @Published var size: Size {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: WidgetOptions.Keys.statusIconSize); item?.refresh() }
    }
    /// Its menu opens when the pointer rests on it, without a click.
    @Published var opensOnHover: Bool {
        didSet { UserDefaults.standard.set(opensOnHover, forKey: WidgetOptions.Keys.statusIconOpensOnHover) }
    }

    private var item: StatusIconItem?
    private var updates: Set<AnyCancellable> = []
    private let signals = StatusSignals()
    /// This feature's hold on the sound outputs list, kept while the icon is on.
    private let outputsHold = UUID()

    /// Debug harnesses never show it: they run under their own bundle identifiers.
    private static var isRealApp: Bool { Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" }

    private init() {
        let defaults = UserDefaults.standard
        isOn = Self.isRealApp && defaults.bool(forKey: WidgetOptions.Keys.statusIconEnabled)
        reading = StatusReading(rawValue: defaults.string(forKey: WidgetOptions.Keys.statusIconReading) ?? "") ?? .combined
        showsValue = defaults.bool(forKey: WidgetOptions.Keys.statusIconShowsValue)
        size = Size(rawValue: defaults.string(forKey: WidgetOptions.Keys.statusIconSize) ?? "") ?? .medium
        opensOnHover = defaults.bool(forKey: WidgetOptions.Keys.statusIconOpensOnHover)
    }

    /// Stored on from an earlier run.
    func startAtLaunch() {
        guard isOn else { return }
        start()
        AppServices.shared.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
    }

    /// The Settings switch and the menu's Turn Off Status Icon.
    func setOn(_ on: Bool) {
        guard Self.isRealApp, on != isOn else { return }
        isOn = on
        UserDefaults.standard.set(on, forKey: WidgetOptions.Keys.statusIconEnabled)
        if on { start() } else { stop() }
        // The readings are sampled only while something shows them.
        AppServices.shared.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
    }

    private func start() {
        guard item == nil else { return }
        let services = AppServices.shared
        signals.start()
        AudioOutputs.shared.setNeeded(true, id: outputsHold)
        item = StatusIconItem(feature: self)
        // A sample changes a dozen values at once: redraw once they've settled, and read Wi-Fi
        // again with each sample.
        Publishers.Merge(services.systemStats.objectWillChange, services.powerMonitor.objectWillChange)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.signals.refresh()
                self?.item?.refresh()
            }
            .store(in: &updates)
        // The volume moves the bar at once.
        signals.objectWillChange
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.item?.refresh() }
            .store(in: &updates)
    }

    private func stop() {
        updates = []
        signals.stop()
        AudioOutputs.shared.setNeeded(false, id: outputsHold)
        item?.remove()
        item = nil
    }

    /// The Mac's readings now.
    var snapshot: StatusSnapshot {
        let stats = AppServices.shared.systemStats, power = AppServices.shared.powerMonitor
        return StatusSnapshot(
            batteryLevel: power.hasBattery && power.hasReading ? power.batteryLevel : nil,
            charging: power.isCharging, onPower: power.isOnExternalPower,
            minutesToEmpty: power.minutesToEmptyShown, minutesToFull: power.minutesToFullShown,
            cpu: stats.cpuUsage, memory: stats.memoryUsage, memoryUsedBytes: stats.memoryUsedBytes,
            disk: stats.diskUsage, diskFreeBytes: stats.diskFreeBytes,
            networkIn: stats.networkInRate, networkOut: stats.networkOutRate,
            wifi: signals.wifi, volume: signals.volume, muted: signals.muted)
    }
}

/// The icon and its menu, there only while the Status icon is on.
@MainActor
final class StatusIconItem: NSObject, NSMenuDelegate {
    private weak var feature: StatusIconFeature?
    private let statusItem: NSStatusItem
    private let entries = StatusIconMenu()
    /// What the icon last drew, so nothing is redrawn for a reading that looks the same.
    private var drawn: (gauge: StatusGauge, value: Bool, size: CGFloat)?
    /// Opens the menu if the pointer is still resting on the icon.
    private var hover: DispatchWorkItem?

    init(feature: StatusIconFeature) {
        self.feature = feature
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        if let button = statusItem.button {
            // `.inVisibleRect` keeps it on the button as the icon changes width.
            button.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        refresh()
    }

    func remove() {
        hover?.cancel()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Open on Hover: the menu opens once the pointer has rested on the icon for a moment, so
    /// passing over it on the way elsewhere opens nothing.
    @objc func mouseEntered(with event: NSEvent) {
        guard feature?.opensOnHover == true else { return }
        hover?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.statusItem.button?.performClick(nil) }
        hover = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    @objc func mouseExited(with event: NSEvent) { hover?.cancel() }

    func refresh() {
        guard let feature, let button = statusItem.button else { return }
        let snapshot = feature.snapshot
        let gauge = StatusGauge.gauge(StatusGauge.shown(feature.reading, snapshot: snapshot), snapshot)
        let size = feature.size.points
        guard drawn?.gauge != gauge || drawn?.value != feature.showsValue || drawn?.size != size else { return }
        drawn = (gauge, feature.showsValue, size)
        button.image = StatusIconImage.image(for: gauge, size: size)
        button.attributedTitle = NSAttributedString(
            string: feature.showsValue ? " " + gauge.value : "",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
        button.toolTip = "\(gauge.reading.title): \(gauge.detail)"
        button.setAccessibilityLabel("\(gauge.reading.title) \(gauge.value)")
    }

    /// A click while the hover wait runs opens the menu first; the wait mustn't reopen it after.
    func menuWillOpen(_ menu: NSMenu) { hover?.cancel() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu, let feature else { return }
        // Devices the Battery widget is already reading; the Status icon never starts that.
        entries.fill(menu, snapshot: feature.snapshot, reading: feature.reading, showsValue: feature.showsValue,
                     devices: AppServices.shared.bluetooth.connectedDevices,
                     outputs: AudioOutputs.shared.outputs, currentOutput: AudioOutputs.shared.currentID,
                     selectOutput: { AudioOutputs.shared.select($0) },
                     choose: { [weak feature] in feature?.reading = $0 },
                     toggleValue: { [weak feature] in feature?.showsValue.toggle() },
                     turnOff: { [weak feature] in feature?.setOn(false) })
    }
}

/// The Status icon's menu, filled afresh each time it opens: every reading with its detail, the
/// ring's one ticked (a click makes another the ring's); Wi-Fi, the volume and the sound outputs
/// to switch between; paired devices' batteries when given; then Show the Number, Open System,
/// Status Icon Settings and Turn Off Status Icon.
@MainActor
final class StatusIconMenu: NSObject {
    private var actions: [ObjectIdentifier: () -> Void] = [:]

    func fill(_ menu: NSMenu, snapshot: StatusSnapshot, reading: StatusReading, showsValue: Bool, devices: [BluetoothDeviceSnapshot],
              outputs: [AudioOutput] = [], currentOutput: AudioDeviceID? = nil, selectOutput: @escaping (AudioDeviceID) -> Void = { _ in },
              choose: @escaping (StatusReading) -> Void, toggleValue: @escaping () -> Void, turnOff: @escaping () -> Void) {
        actions.removeAll()
        menu.removeAllItems()
        let shown = StatusGauge.shown(reading, snapshot: snapshot)
        for reading in StatusGauge.available(snapshot) {
            let gauge = StatusGauge.gauge(reading, snapshot)
            let entry = item(reading.title, menu: menu) { choose(reading) }
            entry.state = reading == shown ? .on : .off
            entry.image = NSImage(systemSymbolName: gauge.symbol, accessibilityDescription: nil)
            entry.attributedTitle = Self.line(reading.title, gauge.detail)
            entry.toolTip = "Show \(reading.title) in the menu bar"
        }
        // What All in One draws beside the battery, in words; and the outputs, one click each.
        if snapshot.wifi != nil || snapshot.volume != nil || outputs.count > 1 { menu.addItem(.separator()) }
        if let wifi = snapshot.wifi {
            let entry = item("Wi-Fi", menu: menu, enabled: false) {}
            entry.image = NSImage(systemSymbolName: wifi.symbol, accessibilityDescription: nil)
            entry.attributedTitle = Self.line("Wi-Fi", wifi.detail)
        }
        if let volume = StatusGauge.volumeDetail(snapshot) {
            let entry = item("Volume", menu: menu, enabled: false) {}
            entry.image = NSImage(systemSymbolName: snapshot.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibilityDescription: nil)
            entry.attributedTitle = Self.line("Volume", volume)
        }
        if outputs.count > 1 {
            let header = item("Sound Output", menu: menu, enabled: false) {}
            header.attributedTitle = NSAttributedString(string: "Sound Output", attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
            ])
            for output in outputs {
                let entry = item(output.name, menu: menu) { selectOutput(output.id) }
                entry.state = output.id == currentOutput ? .on : .off
                entry.image = NSImage(systemSymbolName: output.symbol, accessibilityDescription: nil)
                entry.indentationLevel = 0
            }
        }
        let charged = devices.filter { $0.batteryPercent != nil }
        if !charged.isEmpty {
            menu.addItem(.separator())
            for device in charged {
                let entry = item(device.name, menu: menu, enabled: false) {}
                entry.image = NSImage(systemSymbolName: device.systemImage, accessibilityDescription: nil)
                entry.attributedTitle = Self.line(device.name, "\(device.batteryPercent ?? 0)%")
            }
        }
        menu.addItem(.separator())
        item("Show the Number", menu: menu, action: toggleValue).state = showsValue ? .on : .off
        item("Open System", menu: menu) { NookCommands.open(.system) }
        item("Status Icon Settings", menu: menu) {
            // `show()` with no page: naming one would open it afresh and drop the card.
            SettingsNavigationModel.shared.open(.general, card: StatusIconFeature.card)
            SettingsWindowController.shared.show()
        }
        menu.addItem(.separator())
        item("Turn Off Status Icon", menu: menu, action: turnOff)
    }

    /// A name with its value after it, the value quieter.
    private static func line(_ name: String, _ value: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: name, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        text.append(NSAttributedString(string: "   " + value, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return text
    }

    @discardableResult private func item(_ title: String, menu: NSMenu, enabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runMenuItem(_:)), keyEquivalent: "")
        item.target = self; item.isEnabled = enabled
        actions[ObjectIdentifier(item)] = action
        menu.addItem(item)
        return item
    }

    @objc private func runMenuItem(_ sender: NSMenuItem) { actions[ObjectIdentifier(sender)]?() }

    #if DEBUG
    /// Check renders: clicks the item whose line starts with this name, as the menu would (an
    /// item's title reads back as its whole styled line).
    func click(_ name: String, in menu: NSMenu) {
        if let entry = menu.items.first(where: { $0.title.hasPrefix(name) }) { runMenuItem(entry) }
    }
    #endif
}

extension StatusIconFeature {
    /// The card's name in Settings search.
    static let card = "Status Icon"
}

enum StatusIconImage {
    /// A ring filled clockwise from the top, its symbol in the middle. All in One lights the
    /// Wi-Fi symbol by its strength and adds the volume as a bar beside the ring, crossed when
    /// muted. Drawn as a template (the menu bar's own colour) unless the reading warns: then
    /// orange, or red when critical.
    static func image(for gauge: StatusGauge, size: CGFloat = 18) -> NSImage {
        let colour: NSColor = gauge.level == .critical ? .systemRed : gauge.level == .warning ? .systemOrange : .black
        let barWidth = size * 0.14, barGap = size * 0.12
        let width = size + (gauge.bar != nil ? barGap + barWidth : 0)
        let image = NSImage(size: NSSize(width: width, height: size), flipped: false) { _ in
            let line = size / 9, radius = (size - line) / 2 - size / 18
            let centre = NSPoint(x: size / 2, y: size / 2)
            let track = NSBezierPath()
            track.appendArc(withCenter: centre, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = line
            colour.withAlphaComponent(0.28).setStroke()
            track.stroke()
            if gauge.fraction > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: centre, radius: radius, startAngle: 90, endAngle: 90 - 360 * gauge.fraction, clockwise: true)
                arc.lineWidth = line
                arc.lineCapStyle = .round
                colour.setStroke()
                arc.stroke()
            }
            let config = NSImage.SymbolConfiguration(pointSize: size * 0.4, weight: .bold).applying(.init(paletteColors: [colour]))
            let plain = NSImage(systemSymbolName: gauge.symbol, accessibilityDescription: nil)
            let lit = gauge.symbolStrength.flatMap { NSImage(systemSymbolName: gauge.symbol, variableValue: $0, accessibilityDescription: nil) }
            if let symbol = (lit ?? plain)?.withSymbolConfiguration(config) {
                // Fitted inside the ring, whatever the symbol's own shape.
                let room = (radius - line) * 1.5
                let scale = min(1, room / max(symbol.size.width, symbol.size.height))
                let drawn = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                symbol.draw(in: NSRect(x: centre.x - drawn.width / 2, y: centre.y - drawn.height / 2, width: drawn.width, height: drawn.height))
            }
            if let bar = gauge.bar {
                let height = size * 0.72
                let frame = NSRect(x: size + barGap, y: (size - height) / 2, width: barWidth, height: height)
                colour.withAlphaComponent(0.28).setFill()
                NSBezierPath(roundedRect: frame, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
                if bar > 0 {
                    let filled = NSRect(x: frame.minX, y: frame.minY, width: barWidth, height: max(barWidth, height * bar))
                    colour.setFill()
                    NSBezierPath(roundedRect: filled, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
                }
                if gauge.barMuted {
                    let slash = NSBezierPath()
                    slash.move(to: NSPoint(x: frame.minX - barWidth * 0.6, y: frame.minY + height * 0.2))
                    slash.line(to: NSPoint(x: frame.maxX + barWidth * 0.6, y: frame.maxY - height * 0.2))
                    slash.lineWidth = line * 0.8
                    slash.lineCapStyle = .round
                    colour.setStroke()
                    slash.stroke()
                }
            }
            return true
        }
        image.isTemplate = gauge.level == .normal
        return image
    }
}
