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
    }

    @Published var clockUses24Hour: Bool { didSet { defaults.set(clockUses24Hour, forKey: Keys.clock24) } }
    @Published var clockShowsSeconds: Bool { didSet { defaults.set(clockShowsSeconds, forKey: Keys.clockSeconds) } }
    /// How the Clock looks: the regular big time, or a dot-matrix board.
    enum ClockStyle: String, CaseIterable, Identifiable {
        case regular, dot
        var id: String { rawValue }
        var title: String { self == .regular ? "Regular" : "Dot" }
    }
    @Published var clockStyle: ClockStyle {
        didSet {
            defaults.set(clockStyle.rawValue, forKey: Keys.clockStyle)
            // The Dot style is wider: let Home lay out again.
            Task { @MainActor in NookSettings.shared.objectWillChange.send() }
        }
    }
    /// The Clock's places, in order (time-zone identifiers; "local" is where you are), up to five.
    @Published var clockPlaces: [String] { didSet { defaults.set(clockPlaces, forKey: Keys.clockPlaces) } }
    @Published var temperatureUnit: TemperatureUnit { didSet { defaults.set(temperatureUnit.rawValue, forKey: Keys.unit) } }
    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: Keys.focus) } }
    @Published var breakMinutes: Int { didSet { defaults.set(breakMinutes, forKey: Keys.rest) } }
    @Published var timerPresets: [Int] { didSet { defaults.set(timerPresets, forKey: Keys.presets) } }


    private enum Keys {
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
    }

    static let timerPresetChoices = [1, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let usesMetric = Locale.current.measurementSystem != .us
        defaults.register(defaults: [
            Keys.clock24: Self.localeUses24Hour,
            Keys.clockSeconds: false,
            Keys.clockZone: "",
            Keys.unit: (usesMetric ? TemperatureUnit.celsius : .fahrenheit).rawValue,
            Keys.focus: 25,
            Keys.rest: 5,
            Keys.presets: [5, 15, 25]
        ])
        clockUses24Hour = defaults.bool(forKey: Keys.clock24)
        clockShowsSeconds = defaults.bool(forKey: Keys.clockSeconds)
        clockStyle = ClockStyle(rawValue: defaults.string(forKey: Keys.clockStyle) ?? "") ?? .regular
        temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: Keys.unit) ?? "") ?? .celsius
        focusMinutes = min(max(defaults.integer(forKey: Keys.focus), 5), 120)
        breakMinutes = min(max(defaults.integer(forKey: Keys.rest), 1), 60)
        let presets = (defaults.array(forKey: Keys.presets) as? [Int] ?? []).filter { (1...600).contains($0) }
        timerPresets = presets.isEmpty ? [5, 15, 25] : Array(presets.prefix(3))
        // Places: saved ones, else the World Clock's cities (2.68), else the old second clock.
        let known = Set(Self.worldClockZones.map(\.identifier) + [Self.local])
        let saved = defaults.stringArray(forKey: Keys.clockPlaces)
            ?? defaults.stringArray(forKey: Keys.worldCities)
            ?? [defaults.string(forKey: Keys.clockZone) ?? ""]
        clockPlaces = Array(saved.filter(known.contains).prefix(5))
    }

    static let local = "local"

    /// The Dot board's rows: your places, or a classic five when none are chosen.
    var dotPlaces: [String] { clockPlaces.isEmpty ? Self.defaultWorldCities : clockPlaces }

    static func zone(_ place: String) -> TimeZone? { place == local ? .current : TimeZone(identifier: place) }

    static func placeName(_ place: String) -> String {
        if place == local {
            return worldClockZones.first { $0.identifier == TimeZone.current.identifier }?.title
                ?? TimeZone.current.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "Here"
        }
        return worldClockZones.first { $0.identifier == place }?.title ?? place
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
