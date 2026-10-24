import Foundation
import AppKit
import IOKit
import IOKit.ps
import Combine
import notify
@preconcurrency import UserNotifications

/// Only the internal battery belongs in the Mac's battery tile. Capacity units
/// vary by source, and external power does not necessarily mean charging.
struct MacPowerSnapshot: Equatable {
    let level: Int
    let externalPower: Bool
    let charging: Bool
    /// macOS's "Is Charged" flag.
    var charged = false
    /// macOS's own time to full, in minutes; nil while it has none (-1 or 0).
    var minutesToFull: Int?
    /// macOS's own time to empty on battery, in minutes; nil while it's still
    /// calculating (-1 or 0).
    var minutesToEmpty: Int?

    static func read(_ description: [String: Any]) -> Self? {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              description[kIOPSIsPresentKey] as? Bool != false,
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int,
              maximum > 0, current >= 0 else { return nil }
        let external = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        return Self(level: min(100, Int((Double(current) / Double(maximum) * 100).rounded())),
                    externalPower: external,
                    charging: external && (description[kIOPSIsChargingKey] as? Bool == true),
                    charged: description[kIOPSIsChargedKey] as? Bool == true,
                    minutesToFull: (description[kIOPSTimeToFullChargeKey] as? Int).flatMap { $0 > 0 ? $0 : nil },
                    minutesToEmpty: external ? nil : (description[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil })
    }
}

/// The battery's one state. Every power view and the notice beside the notch read the
/// committed value, which changes only through `BatteryStateDebouncer`.
enum BatteryState: Equatable {
    case unavailable, noBattery, onBattery, low, charging, fullyCharged, notCharging, draining

    var isOnAC: Bool { [.charging, .fullyCharged, .notCharging, .draining].contains(self) }
    var isWarning: Bool { self == .low || self == .draining }
}

/// Maximum capacity and condition exactly as System Information reports them; a value
/// it doesn't report stays nil and is left out.
struct BatteryHealth: Equatable {
    var maximumCapacity: Int?
    var conditionNormal: Bool?
    var fetchedAt: Date

    /// Reads `system_profiler SPPowerDataType -json`: the first dictionary holding the
    /// battery health keys. "Good" is normal; Apple's service wordings are not; anything
    /// else (another wording or language) is left unknown rather than guessed.
    static func parse(_ data: Data, at date: Date = Date()) -> Self? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        func find(_ value: Any) -> [String: Any]? {
            if let dictionary = value as? [String: Any] {
                if dictionary["sppower_battery_health_maximum_capacity"] != nil || dictionary["sppower_battery_health"] != nil {
                    return dictionary
                }
                for key in dictionary.keys.sorted() { if let found = find(dictionary[key]!) { return found } }
            } else if let array = value as? [Any] {
                for element in array { if let found = find(element) { return found } }
            }
            return nil
        }
        let info = find(json)
        let rawCapacity = info?["sppower_battery_health_maximum_capacity"]
        let capacity = (rawCapacity as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
            ?? (rawCapacity as? NSNumber)?.intValue
        let condition: Bool? = (info?["sppower_battery_health"] as? String).flatMap { value in
            if value == "Good" { return true }
            let service = ["Fair", "Poor", "Service Recommended", "Service Battery", "Check Battery", "Replace Soon", "Replace Now"]
            return service.contains { $0.caseInsensitiveCompare(value) == .orderedSame } ? false : nil
        }
        return Self(maximumCapacity: capacity.flatMap { (1...100).contains($0) ? $0 : nil }, conditionNormal: condition, fetchedAt: date)
    }

    /// Runs off the main thread, with a five-second timeout.
    static func load() -> Self? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { return nil }
        return parse(data)
    }
}

/// The charger as macOS describes it (AdapterDetails). `connectionWatts` is what this
/// connection can give, the figure System Information shows as Wattage; `ratedWatts`
/// is the rating in the charger's name.
struct ChargerInfo: Equatable {
    static let placeholderName = "Charger"
    var name: String
    var connectionWatts: Int?
    var ratedWatts: Int?

    init(name: String, connectionWatts: Int?, ratedWatts: Int?) {
        self.name = name; self.connectionWatts = connectionWatts; self.ratedWatts = ratedWatts
    }

    init(adapterDetails adapter: [String: Any]?) {
        let named = (adapter?["Name"] as? String).map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        let described = (adapter?["Description"] as? String).map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0.lowercased() == "pd charger" ? "USB-C charger" : $0 }
        let name = named ?? described ?? Self.placeholderName
        self.init(name: name,
                  connectionWatts: (adapter?["Watts"] as? NSNumber).map(\.intValue).flatMap { $0 > 0 ? $0 : nil },
                  ratedWatts: Self.ratedWatts(in: name))
    }

    /// "140W USB-C Power Adapter" → 140: two or three digits, an optional space, then W.
    static func ratedWatts(in name: String) -> Int? {
        let digits = name.prefix { $0.isASCII && $0.isNumber }
        guard (2...3).contains(digits.count) else { return nil }
        let rest = name.dropFirst(digits.count).drop { $0 == " " }
        guard rest.first == "W", name.dropFirst(digits.count).prefix { $0 == " " }.count <= 1 else { return nil }
        return Int(digits)
    }
}

/// A notice beside the closed notch.
struct PowerNotice: Equatable {
    enum Kind { case pluggedIn, unplugged, low, draining }
    let kind: Kind
    let id: UUID
}

/// Holds back state changes until they've settled, so the views never flicker: an
/// unplug commits at once; a plug-in after two steady seconds (macOS reports power,
/// then charging about a second later, then the charger); and after the first minute
/// on power, charging stopping needs 10 s and starting again 30 s (top-off flips near
/// full). A drain warning and on battery ↔ low commit at once.
struct BatteryStateDebouncer {
    private(set) var committed: BatteryState
    /// When the current stretch on power was committed by a plug-in; nil off power or
    /// when the app started on power.
    private(set) var plugInAt: Date?
    private(set) var candidate: BatteryState?
    private(set) var candidateSince: Date?

    init(_ initial: BatteryState) { committed = initial }

    /// Feeds the latest raw state; returns a state to commit now.
    mutating func feed(_ raw: BatteryState, at now: Date) -> BatteryState? {
        guard raw != committed else { candidate = nil; candidateSince = nil; return nil }
        if dwell(to: raw, at: now) == nil { return commit(raw, at: now) }
        if raw != candidate { candidate = raw; candidateSince = now }
        return poll(at: now)
    }

    /// When the pending candidate commits if it holds.
    var dueDate: Date? {
        guard let candidate, let candidateSince, let wait = dwell(to: candidate, at: candidateSince) else { return nil }
        return candidateSince.addingTimeInterval(wait)
    }

    mutating func poll(at now: Date) -> BatteryState? {
        guard let candidate, let due = dueDate, now.timeIntervalSince(due) >= -0.001 else { return nil }
        return commit(candidate, at: now)
    }

    /// How long a change to `raw` must hold; nil commits at once.
    func dwell(to raw: BatteryState, at time: Date) -> TimeInterval? {
        let from = committed
        if !raw.isOnAC && !from.isOnAC { return nil }
        if from.isOnAC && !raw.isOnAC { return nil }
        if raw == .draining || from == .draining { return nil }
        if !from.isOnAC { return 2 }
        if let plugInAt, time.timeIntervalSince(plugInAt) < 60 { return 2 }
        switch (from, raw) {
        case (.charging, .notCharging): return 10
        case (.fullyCharged, .charging), (.notCharging, .charging): return 30
        default: return 2
        }
    }

    private mutating func commit(_ state: BatteryState, at now: Date) -> BatteryState {
        if !committed.isOnAC && state.isOnAC { plugInAt = now } else if !state.isOnAC { plugInAt = nil }
        committed = state
        candidate = nil; candidateSince = nil
        return state
    }
}

/// The only warning besides low battery: on power for five minutes, the level has
/// fallen three points below its peak, and over the next minute the charger gives at
/// least 85% of what this connection can. Without a connection wattage or a live
/// reading it never fires.
struct DrainDetector {
    private(set) var peakLevel = 0
    private(set) var minLevel = 0
    private(set) var confirmed = false
    /// The level at the last check that didn't confirm; the next waits for a lower one.
    private var checkedLevel: Int?
    var alertedThisStretch = false

    mutating func reset(level: Int) { self = DrainDetector(); peakLevel = level; minLevel = level }

    mutating func track(_ level: Int) {
        if !confirmed { peakLevel = max(peakLevel, level) }
        minLevel = min(minLevel, level)
    }

    func isCandidate(level: Int, onACFor: TimeInterval) -> Bool {
        !confirmed && onACFor >= 300 && level <= peakLevel - 3 && (checkedLevel.map { level < $0 } ?? true)
    }

    static func confirms(mean60: Double?, connectionWatts: Int?, isLive: Bool) -> Bool {
        guard isLive, let connectionWatts, connectionWatts > 0, let mean60 else { return false }
        return mean60 >= 0.85 * Double(connectionWatts)
    }

    /// The candidate and confirmation together, for checks.
    static func fires(peak: Int, level: Int, onACFor: TimeInterval, mean60: Double?, connectionWatts: Int?, isLive: Bool) -> Bool {
        var detector = DrainDetector(); detector.reset(level: peak)
        return detector.isCandidate(level: level, onACFor: onACFor)
            && confirms(mean60: mean60, connectionWatts: connectionWatts, isLive: isLive)
    }

    mutating func confirm(level: Int) { confirmed = true; minLevel = level }
    mutating func checked(level: Int) { checkedLevel = level }
    func recovered(level: Int) -> Bool { confirmed && level >= minLevel + 1 }
    mutating func clear(level: Int) { confirmed = false; peakLevel = level; minLevel = level; checkedLevel = nil }
}

/// macOS's time to full, filtered so it only steps down freely: a higher estimate is
/// taken only when two updates in a row exceed the shown one by 10 minutes or 15%.
struct TimeToFullFilter {
    private(set) var shown: Int?
    private var higher = 0
    /// The last estimate seen. One macOS update can reach refresh() more than once, so
    /// only a changed value counts as a new update.
    private var lastRaw: Int?

    mutating func update(_ minutes: Int) -> Int? {
        defer { lastRaw = minutes }
        guard minutes != lastRaw else { return shown }
        guard let current = shown, minutes > current else { shown = minutes; higher = 0; return shown }
        if Double(minutes - current) >= max(10, Double(current) * 0.15) {
            higher += 1
            if higher >= 2 { shown = minutes; higher = 0 }
        } else {
            higher = 0
        }
        return shown
    }

    mutating func clear() { shown = nil; higher = 0; lastRaw = nil }
}

/// macOS's time to empty moves with every burst of work, so the shown time changes
/// only when a new estimate differs by 15 minutes or 20% (whichever is more) twice in
/// a row in the same direction, and it waits five minutes after unplugging for macOS
/// to settle.
struct TimeToEmptyFilter {
    private(set) var shown: Int?
    private var pending = 0
    private var lastRaw: Int?

    mutating func update(_ minutes: Int, onBatteryFor: TimeInterval?) -> Int? {
        defer { lastRaw = minutes }
        if let onBatteryFor, onBatteryFor < 300 { return nil }
        guard minutes != lastRaw else { return shown }
        guard let current = shown else { shown = minutes; return shown }
        let change = minutes - current
        guard Double(abs(change)) >= max(15, Double(current) * 0.2) else { pending = 0; return shown }
        // Counts up for longer, down for shorter; a change of direction starts over.
        let step = change > 0 ? 1 : -1
        pending = pending.signum() == step ? pending + step : step
        if abs(pending) >= 2 { shown = minutes; pending = 0 }
        return shown
    }

    mutating func clear() { shown = nil; pending = 0; lastRaw = nil }
}

/// Watches the battery through IOKit power sources and keeps the one committed state
/// the views read, the charger macOS reports, System Information's health, and the
/// notices beside the notch. Nothing here is computed from watts except the drain
/// warning's confirmation.
@MainActor
final class PowerSourceMonitor: ObservableObject {
    @Published private(set) var state: BatteryState = .unavailable
    @Published private(set) var batteryLevel: Int = 0
    @Published private(set) var hasBattery = false
    @Published private(set) var hasReading = false
    /// macOS's power source as reported, before any debounce.
    @Published private(set) var isOnExternalPower = false
    var isCharging: Bool { state == .charging }
    /// macOS's time to full while charging, filtered (`TimeToFullFilter`).
    @Published private(set) var minutesToFullShown: Int?
    /// macOS's time to empty on battery, filtered (`TimeToEmptyFilter`).
    @Published private(set) var minutesToEmptyShown: Int?
    /// When the Mac was unplugged; nil on power or after starting on battery.
    @Published private(set) var onBatterySince: Date?
    @Published private(set) var health: BatteryHealth?
    @Published private(set) var cycleCount: Int?
    /// Whole degrees Celsius, changing only by 0.7 °C or more.
    @Published private(set) var temperatureC: Int?
    /// The charger while on power.
    @Published private(set) var charger: ChargerInfo?
    /// The last charger this session, for the unplugged cable card.
    @Published private(set) var lastCharger: ChargerInfo?
    /// True for up to ten seconds after plugging in while macOS hasn't described the charger.
    @Published private(set) var isReadingCharger = false
    /// The level a confirmed drain started from.
    @Published private(set) var drainFromLevel: Int?
    @Published private(set) var notice: PowerNotice?
    /// True while a notice shows beside the notch.
    @Published private(set) var justChangedRecently = false
    /// The live input reading, sampled only while something holds it.
    let input = PowerInputSampler()

    private var runLoopSource: CFRunLoopSource?
    private var notifyToken: Int32 = NOTIFY_TOKEN_INVALID
    private var wakeObserver: NSObjectProtocol?
    private var hideWorkItem: DispatchWorkItem?
    private var debounceWork: DispatchWorkItem?
    private var registryRereads: [DispatchWorkItem] = []
    private var drainCheck: DispatchWorkItem?
    private var chargingRecheck: DispatchWorkItem?
    private var healthTimer: Timer?
    private var temperatureTimer: Timer?
    private var detailsShown = 0
    private var healthFetchInFlight = false
    private var seeded = false
    private var debouncer = BatteryStateDebouncer(.unavailable)
    private var timeFilter = TimeToFullFilter()
    private var emptyFilter = TimeToEmptyFilter()
    private var drain = DrainDetector()
    private var latest: MacPowerSnapshot?
    private var adapter: [String: Any]?
    private var acSince: Date?
    private var chargingFlagSince: Date?
    private var previousBatteryLevel: Int?
    private var lastWake: Date?
#if DEBUG
    private var isPreview = false
#endif

    func start() {
        guard runLoopSource == nil else { return }
        refresh()

        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                monitor.refresh()
            }
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        var token: Int32 = 0
        if notify_register_dispatch(kIOPSNotifyTimeRemaining, &token, .main, { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }) == NOTIFY_STATUS_OK {
            notifyToken = token
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.lastWake = Date()
                self?.timeFilter.clear(); self?.set(\.minutesToFullShown, nil)
                self?.emptyFilter.clear(); self?.set(\.minutesToEmptyShown, nil)
                self?.refresh(); self?.input.reset()
            }
        }
        fetchHealth()
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetchHealth() }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if notifyToken != NOTIFY_TOKEN_INVALID { notify_cancel(notifyToken); notifyToken = NOTIFY_TOKEN_INVALID }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver); self.wakeObserver = nil }
        hideWorkItem?.cancel(); hideWorkItem = nil
        debounceWork?.cancel(); debounceWork = nil
        chargingRecheck?.cancel(); chargingRecheck = nil
        cancelRegistryRereads()
        cancelDrainCheck()
        healthTimer?.invalidate(); healthTimer = nil
        temperatureTimer?.invalidate(); temperatureTimer = nil
        justChangedRecently = false
        notice = nil
        previousBatteryLevel = nil
        seeded = false
        // A restart starts a new session: nothing carries over from before.
        drain = DrainDetector()
        timeFilter.clear()
        emptyFilter.clear()
        minutesToEmptyShown = nil
        acSince = nil
        chargingFlagSince = nil
        minutesToFullShown = nil
        onBatterySince = nil
        drainFromLevel = nil
    }

    // MARK: Reading

    private func refresh() {
        let now = Date()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        let descriptions = sources.compactMap { source in
            IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        }
        guard let snapshot = descriptions.compactMap(MacPowerSnapshot.read).first else {
            // Missing capacity data is unknown, not a desktop or a full battery.
            let battery = descriptions.contains { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
            set(\.hasBattery, battery)
            set(\.hasReading, !battery)
            latest = nil
            apply(rawState, at: now)
            return
        }
        latest = snapshot
        set(\.hasBattery, true)
        set(\.hasReading, true)
        set(\.batteryLevel, snapshot.level)
        set(\.isOnExternalPower, snapshot.externalPower)
        if snapshot.charging { chargingFlagSince = chargingFlagSince ?? now } else { chargingFlagSince = nil }
        readRegistry()
        updateDrain(snapshot, at: now)
        apply(rawState, at: now)
        updateTimeToFull()
        updateTimeToEmpty(at: now)
        if seeded, !state.isOnAC, let old = previousBatteryLevel,
           Self.lowBatteryThresholdCrossed(from: old, to: batteryLevel) {
            post(.low)
            deliverNotification(id: "low-battery.\(batteryLevel)", title: "Low battery", body: "Your Mac is at \(batteryLevel)%.")
        }
        previousBatteryLevel = batteryLevel
    }

    /// The state the latest reading describes, before any debounce.
    private var rawState: BatteryState {
        guard hasReading, hasBattery, let snapshot = latest else { return hasReading ? .noBattery : .unavailable }
        if snapshot.externalPower, drain.confirmed { return .draining }
        return Self.rawState(hasReading: true, hasBattery: true, onAC: snapshot.externalPower, level: snapshot.level,
                             isCharging: snapshot.charging, isCharged: snapshot.charged, wasLow: state == .low)
    }

    /// Low enters at 20% and, once low on battery, holds until 23%. Full wins over a
    /// top-off trickle, so the bolt doesn't flicker at 100%.
    static func rawState(hasReading: Bool, hasBattery: Bool, onAC: Bool, level: Int,
                         isCharging: Bool, isCharged: Bool, wasLow: Bool = false) -> BatteryState {
        guard hasReading else { return .unavailable }
        guard hasBattery else { return .noBattery }
        if !onAC { return level <= 20 || (wasLow && level < 23) ? .low : .onBattery }
        if level >= 100 || (isCharged && level >= 95) { return .fullyCharged }
        return isCharging ? .charging : .notCharging
    }

    /// The battery service's cycle count, charger details and pack temperature. Read on
    /// each power source change, shortly after plugging in, and each minute while the
    /// battery details are open; never polled every second.
    private func readRegistry(temperatureOnly: Bool = false) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if let celsius = (Self.packData(of: service)?["Temperature"] as? NSNumber).map({ Double($0.intValue) / 100 }),
           celsius > 0, celsius < 90,
           temperatureC.map({ abs(celsius - Double($0)) >= 0.7 }) ?? true {
            set(\.temperatureC, Int(celsius.rounded()))
        }
        guard !temperatureOnly else { return }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return }
        set(\.cycleCount, (properties["CycleCount"] as? NSNumber)?.intValue)
        adapter = properties["ExternalConnected"] as? Bool == true ? properties["AdapterDetails"] as? [String: Any] : nil
        updateCharger()
    }

    /// Recent macOS keeps the temperature in the AppleSmartBatteryPack child's
    /// BatteryData rather than on AppleSmartBattery itself.
    private static func packData(of service: io_registry_entry_t) -> [String: Any]? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, "AppleSmartBatteryPack") != 0 else { continue }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(child, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
            return properties["BatteryData"] as? [String: Any]
        }
        return nil
    }

    private func updateCharger() {
        guard state.isOnAC else { return }
        let info = ChargerInfo(adapterDetails: adapter)
        // At unplug the registry already reads disconnected before the commit; keep the
        // last real charger so "Last charger" can name it.
        if info.name == ChargerInfo.placeholderName, adapter == nil, let charger, charger.name != ChargerInfo.placeholderName { return }
        set(\.charger, info)
        input.connectionWatts = info.connectionWatts
        if info.connectionWatts != nil { set(\.isReadingCharger, false) }
    }

    private func updateTimeToFull() {
        guard state == .charging else { return }
        // While macOS recalculates (-1, e.g. after wake) there's no time, rather than a stale one.
        if let minutes = latest?.minutesToFull { set(\.minutesToFullShown, timeFilter.update(minutes)) }
        else { set(\.minutesToFullShown, nil); timeFilter.clear() }
    }

    private func updateTimeToEmpty(at now: Date) {
        guard state == .onBattery || state == .low else { return }
        if let minutes = latest?.minutesToEmpty {
            set(\.minutesToEmptyShown, emptyFilter.update(minutes, onBatteryFor: onBatterySince.map { now.timeIntervalSince($0) }))
        } else {
            set(\.minutesToEmptyShown, nil); emptyFilter.clear()
        }
    }

    // MARK: State

    private func apply(_ raw: BatteryState, at now: Date) {
        guard seeded else {
            seeded = true
            debouncer = BatteryStateDebouncer(raw)
            commit(raw, at: now, announce: false)
            return
        }
        if let next = debouncer.feed(raw, at: now) { commit(next, at: now) }
        scheduleDebounce()
    }

    private func scheduleDebounce() {
        debounceWork?.cancel(); debounceWork = nil
        guard let due = debouncer.dueDate else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let now = Date()
            if let next = self.debouncer.poll(at: now) { self.commit(next, at: now) }
            self.scheduleDebounce()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, due.timeIntervalSinceNow) + 0.02, execute: work)
    }

    private func commit(_ new: BatteryState, at now: Date, announce: Bool = true) {
        let old = state
        let wasOnACFor = acSince.map { now.timeIntervalSince($0) } ?? 0
        set(\.state, new)
        if !old.isOnAC && new.isOnAC {
            acSince = now
            drain.reset(level: batteryLevel)
            set(\.onBatterySince, nil)
            set(\.drainFromLevel, nil)
            readRegistry()
            set(\.isReadingCharger, announce && charger?.connectionWatts == nil)
            if announce { scheduleRegistryRereads(); post(.pluggedIn) }
        } else if old.isOnAC && !new.isOnAC {
            if let charger, charger.name != ChargerInfo.placeholderName { set(\.lastCharger, charger) }
            set(\.charger, nil)
            set(\.isReadingCharger, false)
            set(\.drainFromLevel, nil)
            input.connectionWatts = nil
            cancelRegistryRereads()
            cancelDrainCheck()
            drain.clear(level: batteryLevel)
            chargingFlagSince = nil
            chargingRecheck?.cancel(); chargingRecheck = nil
            acSince = nil
            if announce {
                // Unplugged while asleep: the moment is unknown, so no "for …" time.
                let justWoke = lastWake.map { now.timeIntervalSince($0) < 10 } ?? false
                set(\.onBatterySince, justWoke ? nil : now)
                if wasOnACFor >= 2 { post(.unplugged) }
            }
        }
        if new != .charging { set(\.minutesToFullShown, nil); timeFilter.clear() }
        if old.isOnAC != new.isOnAC { input.reset() }
        if new == .charging { updateTimeToFull() }
        if new.isOnAC || new == .noBattery || new == .unavailable { set(\.minutesToEmptyShown, nil); emptyFilter.clear() }
        if new == .onBattery || new == .low { updateTimeToEmpty(at: now) }
    }

    /// AdapterDetails fills in a few seconds after plugging in.
    private func scheduleRegistryRereads() {
        cancelRegistryRereads()
        for delay in [3.0, 10.0] {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.state.isOnAC else { return }
                self.readRegistry()
                if delay >= 10 { self.set(\.isReadingCharger, false) }
            }
            registryRereads.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func cancelRegistryRereads() {
        registryRereads.forEach { $0.cancel() }
        registryRereads = []
    }

    // MARK: Drain warning

    private func updateDrain(_ snapshot: MacPowerSnapshot, at now: Date) {
        guard state.isOnAC, snapshot.externalPower else { return }
        drain.track(snapshot.level)
        if drain.confirmed {
            let chargingHeld = chargingFlagSince.map { now.timeIntervalSince($0) >= 60 } ?? false
            if drain.recovered(level: snapshot.level) || chargingHeld {
                drain.clear(level: snapshot.level)
                set(\.drainFromLevel, nil)
            } else if let since = chargingFlagSince {
                // Charging that holds for a minute clears the warning; look again then.
                chargingRecheck?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.refresh() }
                chargingRecheck = work
                DispatchQueue.main.asyncAfter(deadline: .now() + max(1, 60 - now.timeIntervalSince(since)), execute: work)
            }
            return
        }
        guard drainCheck == nil, let acSince, drain.isCandidate(level: snapshot.level, onACFor: now.timeIntervalSince(acSince)) else { return }
        input.beginDrainWindow()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let mean = self.input.endDrainWindow()
            self.drainCheck = nil
            guard self.state.isOnAC else { return }
            guard DrainDetector.confirms(mean60: mean, connectionWatts: self.charger?.connectionWatts, isLive: self.input.isLive) else {
                self.drain.checked(level: self.batteryLevel)
                return
            }
            self.drain.confirm(level: self.batteryLevel)
            // Only charging that starts after the warning clears it.
            self.chargingFlagSince = nil
            self.set(\.drainFromLevel, self.drain.peakLevel)
            self.apply(self.rawState, at: Date())
            guard !self.drain.alertedThisStretch else { return }
            self.drain.alertedThisStretch = true
            self.post(.draining)
            let watts = self.charger?.connectionWatts.map { "\($0) W " } ?? ""
            self.deliverNotification(id: "draining", title: "Charger can't keep up",
                                     body: "Your Mac is plugged in, but its battery fell from \(self.drain.peakLevel)% to \(self.batteryLevel)% while the \(watts)charger gives all it can. Use a stronger charger or plug straight into the Mac.")
        }
        drainCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    private func cancelDrainCheck() {
        guard let drainCheck else { return }
        drainCheck.cancel()
        self.drainCheck = nil
        _ = input.endDrainWindow()
    }

    // MARK: Health and details

    /// The battery popover is open: health if it's over an hour old, and the
    /// temperature once a minute.
    func beginDetails() {
        detailsShown += 1
        refreshHealthIfStale()
        guard temperatureTimer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readRegistry(temperatureOnly: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        temperatureTimer = timer
    }

    func endDetails() {
        detailsShown = max(0, detailsShown - 1)
        guard detailsShown == 0 else { return }
        temperatureTimer?.invalidate(); temperatureTimer = nil
    }

    func refreshHealthIfStale() {
        guard health.map({ Date().timeIntervalSince($0.fetchedAt) > 3600 }) ?? true else { return }
        fetchHealth()
    }

    private func fetchHealth() {
#if DEBUG
        guard !isPreview else { return }
#endif
        guard !healthFetchInFlight else { return }
        healthFetchInFlight = true
        DispatchQueue.global(qos: .utility).async {
            let loaded = BatteryHealth.load()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.healthFetchInFlight = false
                // A failed read still counts as fetched, with nothing to show.
                self.set(\.health, loaded ?? BatteryHealth(maximumCapacity: self.health?.maximumCapacity,
                                                           conditionNormal: self.health?.conditionNormal, fetchedAt: Date()))
            }
        }
    }

    // MARK: Notices

    /// Notices come only from commits and the drain detector. A notice of the kind
    /// already showing is merged; any other replaces it.
    private func post(_ kind: PowerNotice.Kind) {
        guard hasReading, hasBattery else { return }
        if justChangedRecently, notice?.kind == kind { return }
        showTemporarily(PowerNotice(kind: kind, id: UUID()), duration: kind == .low || kind == .draining ? 8 : 4)
    }

    private func showTemporarily(_ notice: PowerNotice, duration: TimeInterval) {
        hideWorkItem?.cancel()
        self.notice = notice
        justChangedRecently = true

        let work = DispatchWorkItem { [weak self] in
            self?.notice = nil
            self?.justChangedRecently = false
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    static func lowBatteryThresholdCrossed(from old: Int, to new: Int) -> Bool {
        guard new < old else { return false }
        return [20, 10, 5].contains { old > $0 && new <= $0 }
    }

    private func deliverNotification(id: String, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let deliver = {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                center.add(
                    UNNotificationRequest(
                        identifier: "dev.opensource.MacSpaces.\(id)",
                        content: content,
                        trigger: nil
                    )
                )
            }

            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { deliver() }
                }
            case .authorized, .provisional:
                deliver()
            default:
                break
            }
        }
    }

    /// Publishes only real changes, so views and the notch window don't redraw for nothing.
    private func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<PowerSourceMonitor, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

#if DEBUG
    func setPreview(level: Int, externalPower: Bool = false, charging: Bool = false, activity: Bool = true) {
        let level = min(100, max(0, level))
        let state = Self.rawState(hasReading: true, hasBattery: true, onAC: externalPower, level: level,
                                  isCharging: charging && externalPower, isCharged: false)
        setPreview(state: state, level: level, activity: activity)
    }

    /// Synthetic values for captures; nothing here reads the real battery.
    func setPreview(state: BatteryState, level: Int, minutesToFull: Int? = nil, minutesToEmpty: Int? = nil, onBatterySince: Date? = nil,
                    health: BatteryHealth? = nil, cycles: Int? = nil, temperatureC: Int? = nil,
                    charger: ChargerInfo? = nil, lastCharger: ChargerInfo? = nil, readingCharger: Bool = false,
                    drainFrom: Int? = nil, activity: Bool = false) {
        isPreview = true
        hasBattery = state != .noBattery; hasReading = state != .unavailable
        batteryLevel = min(100, max(0, level))
        isOnExternalPower = state.isOnAC
        self.state = state
        minutesToFullShown = state == .charging ? minutesToFull : nil
        minutesToEmptyShown = state.isOnAC ? nil : minutesToEmpty
        self.onBatterySince = state.isOnAC ? nil : onBatterySince
        self.health = health; cycleCount = cycles; self.temperatureC = temperatureC
        self.charger = state.isOnAC ? charger : nil
        self.lastCharger = lastCharger
        isReadingCharger = readingCharger
        drainFromLevel = state == .draining ? drainFrom : nil
        input.connectionWatts = self.charger?.connectionWatts
        let kind: PowerNotice.Kind = state.isWarning ? (state == .low ? .low : .draining) : state.isOnAC ? .pluggedIn : .unplugged
        notice = activity ? PowerNotice(kind: kind, id: UUID()) : nil
        justChangedRecently = activity
    }
#endif

    deinit {
        // The IOKit callback holds an unretained pointer to self; invalidate
        // the source (thread-safe, detaches from all run loops) so it can
        // never fire after deallocation. CFRunLoopRemoveSource would only be
        // safe from the main thread, which deinit is not guaranteed to be on.
        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if notifyToken != NOTIFY_TOKEN_INVALID { notify_cancel(notifyToken) }
        hideWorkItem?.cancel()
    }
}

/// The charger's live input from the SMC (PDTR watts, VD0R volts), sampled once a
/// second only while something holds it: the Cable management card, and a drain
/// warning's one-minute check. Values are published display-ready, so views redraw
/// only when what they show changes.
@MainActor
final class PowerInputSampler: ObservableObject {
    /// The 30-second mean, in whole watts; nil until three seconds of samples exist
    /// after plugging in or waking. It moves only by 2 W or 8%, whichever is more, and
    /// it's kept while nothing holds the sampler, so reopening shows it straight away.
    @Published private(set) var shownWatts: Int?
    /// The USB-C step the charger supplies ("28 V"), or one decimal off the steps.
    @Published private(set) var shownStep: String?
    /// Thirty seconds at 95% or more of what the connection can give.
    @Published private(set) var atLimit = false
    /// False after ten seconds without a reading.
    @Published private(set) var isLive = false
    /// What this connection can give (AdapterDetails Watts); set by the monitor.
    var connectionWatts: Int? {
        didSet { if connectionWatts == nil, atLimit { atLimit = false } }
    }

    private struct Sample { let date: Date; let watts: Double; let volts: Double? }
    private var holders = 0
    private var timer: Timer?
    private var samples: [Sample] = []
    private var lastGood: Date?
    private var failingSince: Date?
    private var lastTick: Date?
    private var lastEvaluation: Date?
    private var steps = StepFilter()
    private var limit = LimitTracker()
    private var drainWatts: [Double]?
#if DEBUG
    private var isPreview = false
#endif

    func retain() {
        holders += 1
        guard holders == 1 else { return }
#if DEBUG
        if isPreview { return }
#endif
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func release() {
        guard holders > 0 else { return }
        holders -= 1
        guard holders == 0 else { return }
        timer?.invalidate(); timer = nil
#if DEBUG
        if isPreview { return }
#endif
        forgetSamples()
    }

    /// Starts the drain check's one-minute mean.
    func beginDrainWindow() {
        drainWatts = []
        retain()
    }

    /// Ends the drain check; the mean of every reading since it began.
    func endDrainWindow() -> Double? {
        guard let watts = drainWatts else { return nil }
        drainWatts = nil
        release()
        return watts.isEmpty ? nil : watts.reduce(0, +) / Double(watts.count)
    }

    /// Forgets every sample and the shown values: on plugging in or unplugging, and
    /// on waking.
    func reset() {
#if DEBUG
        if isPreview { return }
#endif
        forgetSamples()
        if drainWatts != nil { drainWatts = [] }
        if shownWatts != nil { shownWatts = nil }
        if shownStep != nil { shownStep = nil }
        if atLimit { atLimit = false }
    }

    /// Forgets the samples but keeps what's shown until the next mean replaces it: on
    /// the last release, and after a gap of more than five seconds.
    private func forgetSamples() {
        samples = []
        lastGood = nil
        lastTick = nil
        lastEvaluation = nil
        steps = StepFilter()
        limit = LimitTracker()
    }

    private func tick() {
        let now = Date()
        if let lastTick, now.timeIntervalSince(lastTick) > 5 { forgetSamples() }
        lastTick = now
        if let reading = SMCPowerSensors.shared.read(), let watts = reading.inputWatts, watts.isFinite, watts >= 0 {
            samples.append(Sample(date: now, watts: watts, volts: reading.inputVolts))
            lastGood = now
            failingSince = nil
            drainWatts?.append(watts)
            if !isLive { isLive = true }
        } else {
            let since = failingSince ?? now
            failingSince = since
            if isLive, now.timeIntervalSince(since) >= 10 { isLive = false }
        }
        samples.removeAll { now.timeIntervalSince($0.date) > 30 }
        // The first value after plugging in comes from three seconds of samples; later
        // ones wait for ten, so a fresh window doesn't replace a settled reading.
        guard let first = samples.first, now.timeIntervalSince(first.date) >= (shownWatts == nil ? 2.5 : 9.5) else { return }
        let volts = samples.compactMap(\.volts)
        if !volts.isEmpty, let step = steps.feed(Self.step(forVolts: volts.reduce(0, +) / Double(volts.count))), step != shownStep {
            shownStep = step
        }
        guard lastEvaluation.map({ now.timeIntervalSince($0) >= 4.5 }) ?? true else { return }
        lastEvaluation = now
        let mean = samples.map(\.watts).reduce(0, +) / Double(samples.count)
        let watts = Self.nextWatts(shown: shownWatts, mean: mean)
        if watts != shownWatts { shownWatts = watts }
        let limited = limit.feed(mean: mean, connectionWatts: connectionWatts)
        if limited != atLimit { atLimit = limited }
    }

    /// The shown watts after a new mean: unchanged unless it moved by 2 W or 8%.
    static func nextWatts(shown: Int?, mean: Double) -> Int {
        guard let shown, abs(mean - Double(shown)) < max(2, Double(shown) * 0.08) else { return Int(mean.rounded()) }
        return shown
    }

    /// USB-C power steps; a mean within 10% of one shows as that step.
    static let usbSteps: [Double] = [5, 9, 15, 20, 28, 36, 48]

    static func step(forVolts volts: Double) -> String {
        if let nearest = usbSteps.min(by: { abs($0 - volts) < abs($1 - volts) }), abs(nearest - volts) <= nearest * 0.1 {
            return "\(Int(nearest)) V"
        }
        return String(format: "%.1f V", volts)
    }

    /// The shown step changes only after a new one holds for ten readings in a row.
    struct StepFilter {
        private(set) var shown: String?
        private var candidate: String?
        private var count = 0

        mutating func feed(_ step: String) -> String? {
            guard let current = shown else { shown = step; return shown }
            if step == current { candidate = nil; count = 0; return shown }
            if step == candidate { count += 1 } else { candidate = step; count = 1 }
            if count >= 10 { shown = step; candidate = nil; count = 0 }
            return shown
        }
    }

    /// At the limit after six evaluations (30 s) at 95% or more; off after six under 85%.
    struct LimitTracker {
        private(set) var atLimit = false
        private var high = 0
        private var low = 0

        mutating func feed(mean: Double, connectionWatts: Int?) -> Bool {
            guard let connectionWatts, connectionWatts > 0 else { self = LimitTracker(); return false }
            let share = mean / Double(connectionWatts)
            high = share >= 0.95 ? high + 1 : 0
            low = share < 0.85 ? low + 1 : 0
            if high >= 6 { atLimit = true }
            if low >= 6 { atLimit = false }
            return atLimit
        }
    }

#if DEBUG
    /// Synthetic values for captures; the SMC is never read.
    func setPreview(watts: Int?, step: String?, atLimit: Bool = false, isLive: Bool = true) {
        isPreview = true
        timer?.invalidate(); timer = nil
        shownWatts = watts; shownStep = step
        self.atLimit = atLimit; self.isLive = isLive
    }
#endif
}
