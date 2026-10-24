import Foundation
import Combine

/// Preferences that belong to a widget rather than to a profile layout.
/// Shared by every profile so a clock reads the same wherever it appears.
@MainActor
final class WidgetOptions: ObservableObject {
    static let shared = WidgetOptions()

    enum TemperatureUnit: String, CaseIterable, Identifiable {
        case celsius, fahrenheit
        var id: String { rawValue }
        var title: String { self == .celsius ? "Celsius" : "Fahrenheit" }
        var symbol: String { self == .celsius ? "°C" : "°F" }
        static func preferred(in locale: Locale = .autoupdatingCurrent) -> Self {
            UnitTemperature(forLocale: locale, usage: .weather).symbol == UnitTemperature.fahrenheit.symbol ? .fahrenheit : .celsius
        }
    }

    var clockUses24Hour: Bool { Self.localeUses24Hour }
    var clockShowsSeconds: Bool { false }
    /// How the Clock looks: the regular big time, a dot-matrix board, or a world map.
    enum ClockStyle: String, CaseIterable, Identifiable {
        case regular, dot, map
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        /// Dot and Map need a wider tile than Regular.
        var isWide: Bool { self != .regular }
    }
    /// A pin dropped on the Map clock: the spot, and the time zone nearest to it.
    struct ClockPin: Codable, Equatable {
        var latitude: Double
        var longitude: Double
        var zone: String
        var name: String
        /// The country there, when known ("Spain"); nil over the sea.
        var country: String? = nil
    }
    @Published var clockPin: ClockPin? {
        didSet { defaults.set(clockPin.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.clockPin) }
    }
    @Published var clockStyle: ClockStyle {
        didSet {
            defaults.set(clockStyle.rawValue, forKey: Keys.clockStyle)
            // Dot and Map are wider: let Home lay out again.
            Task { @MainActor in NookSettings.shared.objectWillChange.send() }
        }
    }
    /// The Clock's places, in order (time-zone identifiers; "local" is where you are), up to `maxPlaces`.
    @Published var clockPlaces: [String] { didSet { defaults.set(clockPlaces, forKey: Keys.clockPlaces) } }
    @Published private(set) var temperatureUnit: TemperatureUnit
    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: Keys.focus) } }
    @Published var breakMinutes: Int { didSet { defaults.set(breakMinutes, forKey: Keys.rest) } }
    @Published var timerPresets: [Int] { didSet { defaults.set(timerPresets, forKey: Keys.presets) } }


    enum Keys {
        static let clock24 = "widget.clock.24h"
        static let clockSeconds = "widget.clock.seconds"
        static let clockZone = "widget.clock.secondZone"
        static let unit = "widget.weather.unit"
        static let focus = "widget.pomodoro.focus"
        static let rest = "widget.pomodoro.break"
        static let presets = "widget.timer.presets"
        static let worldCities = "widget.worldClock.cities"   // 2.68–2.69 World Clock, read once
        static let clockStyle = "widget.clock.style"
        static let clockPlaces = "widget.clock.places"
        static let clockPin = "widget.clock.pin"
    }

    static let timerPresetChoices = [1, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90]

    private let defaults: UserDefaults
    private var localeObserver: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.clock24: Self.localeUses24Hour,
            Keys.clockSeconds: false,
            Keys.clockZone: "",
            Keys.focus: 25,
            Keys.rest: 5,
            Keys.presets: [5, 15, 25]
        ])
        clockStyle = ClockStyle(rawValue: defaults.string(forKey: Keys.clockStyle) ?? "") ?? .regular
        clockPin = defaults.data(forKey: Keys.clockPin).flatMap { try? JSONDecoder().decode(ClockPin.self, from: $0) }
        temperatureUnit = .preferred()
        focusMinutes = min(max(defaults.integer(forKey: Keys.focus), 5), 120)
        breakMinutes = min(max(defaults.integer(forKey: Keys.rest), 1), 60)
        let presets = (defaults.array(forKey: Keys.presets) as? [Int] ?? []).filter { (1...600).contains($0) }
        timerPresets = presets.isEmpty ? [5, 15, 25] : Array(presets.prefix(3))
        // Places: saved ones, else the World Clock's cities (2.68), else the old second clock.
        // Any real time zone can be a place (the Clock page searches them all).
        let saved = defaults.stringArray(forKey: Keys.clockPlaces)
            ?? defaults.stringArray(forKey: Keys.worldCities)
            ?? [defaults.string(forKey: Keys.clockZone) ?? ""]
        clockPlaces = Array(saved.filter { $0 == Self.local || TimeZone(identifier: Self.zoneIdentifier($0)) != nil }.prefix(Self.maxPlaces))
        localeObserver = NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let unit = TemperatureUnit.preferred()
                    if self.temperatureUnit != unit { self.temperatureUnit = unit }
                    else { self.objectWillChange.send() }
                }
            }
    }

    static let local = "local"
    static let maxPlaces = 6

    /// Adds a place at the end, unless it's already there or the list is full.
    func addPlace(_ place: String) {
        guard !clockPlaces.contains(place), clockPlaces.count < Self.maxPlaces else { return }
        clockPlaces.append(place)
    }

    /// The Dot board's rows: your places, or a classic five when none are chosen.
    var dotPlaces: [String] { clockPlaces.isEmpty ? Self.defaultWorldCities : clockPlaces }

    /// A place is a zone identifier, or "zone#Name#latitude,longitude" for a place found
    /// by search that isn't a zone's own city ("America/Chicago#Madison#43.07,-89.40").
    nonisolated static func namedPlace(zone: String, name: String, latitude: Double, longitude: Double) -> String {
        let clean = name.replacingOccurrences(of: "#", with: " ")
        return "\(zone)#\(clean)#\(String(format: "%.3f,%.3f", latitude, longitude))"
    }

    nonisolated static func zoneIdentifier(_ place: String) -> String {
        place.split(separator: "#", maxSplits: 1).first.map(String.init) ?? place
    }

    /// The position saved with a searched place, if any.
    nonisolated static func savedPosition(_ place: String) -> (latitude: Double, longitude: Double)? {
        let parts = place.split(separator: "#")
        guard parts.count == 3 else { return nil }
        let numbers = parts[2].split(separator: ",").compactMap { Double($0) }
        return numbers.count == 2 ? (numbers[0], numbers[1]) : nil
    }

    static func zone(_ place: String) -> TimeZone? { place == local ? .current : TimeZone(identifier: zoneIdentifier(place)) }

    /// A saved place in this Mac's time zone stands for where you are: the Map draws it as
    /// the current place instead of a second "local" pin (owner).
    static func isCurrent(_ place: String) -> Bool {
        place == local || zoneIdentifier(place) == TimeZone.current.identifier
    }

    static func placeName(_ place: String) -> String {
        let parts = place.split(separator: "#")
        if parts.count >= 2 { return String(parts[1]) }
        if place == local {
            return worldClockZones.first { $0.identifier == TimeZone.current.identifier }?.title
                ?? TimeZone.current.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "Here"
        }
        return worldClockZones.first { $0.identifier == place }?.title ?? ClockGeography.cityName(place)
    }

    private static var localeUses24Hour: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !format.contains("a")
    }

    static let defaultWorldCities = ["America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Dubai", "Asia/Tokyo"]

    /// A short, curated list keeps the picker usable; the user's own zone is excluded.
    static let worldClockZones: [(title: String, identifier: String)] = [
        ("Los Angeles", "America/Los_Angeles"), ("Denver", "America/Denver"), ("Chicago", "America/Chicago"),
        ("New York", "America/New_York"), ("São Paulo", "America/Sao_Paulo"), ("London", "Europe/London"),
        ("Paris", "Europe/Paris"), ("Berlin", "Europe/Berlin"), ("Dubai", "Asia/Dubai"),
        ("Mumbai", "Asia/Kolkata"), ("Singapore", "Asia/Singapore"), ("Shanghai", "Asia/Shanghai"),
        ("Tokyo", "Asia/Tokyo"), ("Sydney", "Australia/Sydney"), ("Auckland", "Pacific/Auckland")
    ]
}
