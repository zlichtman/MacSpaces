import Foundation
import Combine

/// The Music page's look: the standard page, or Terminal (a monospaced card with an ASCII cover).
enum MusicLook: String, CaseIterable, Identifiable {
    case standard, terminal, shelf
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "Standard"
        case .terminal: return "Vinyl"
        case .shelf: return "Shelf"
        }
    }
}

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
    @Published var timerPresets: [Int] { didSet { defaults.set(timerPresets, forKey: Keys.presets) } }
    /// The Calendar page's Life view: your birthday (kept only on this Mac) and the age it counts to.
    @Published var birthday: Date? { didSet { defaults.set(birthday?.timeIntervalSince1970, forKey: Keys.birthday) } }
    @Published var lifespan: Int { didSet { defaults.set(lifespan, forKey: Keys.lifespan) } }
    /// The Music page's cover as live ASCII art (Settings → Appearance → Album art); off is the artwork.
    @Published var asciiCover: Bool { didSet { defaults.set(asciiCover, forKey: Keys.asciiCover) } }
    @Published var asciiStyle: AsciiStyle { didSet { defaults.set(asciiStyle.rawValue, forKey: Keys.asciiStyle) } }
    @Published var asciiScene: AsciiScene { didSet { defaults.set(asciiScene.rawValue, forKey: Keys.asciiScene) } }
    /// What moves around and behind the ASCII scene; off (the default) draws only the scene.
    @Published var asciiAround: AsciiAround { didSet { defaults.set(asciiAround.rawValue, forKey: Keys.asciiAround) } }
    @Published var asciiDetail: AsciiDetail { didSet { defaults.set(asciiDetail.rawValue, forKey: Keys.asciiDetail) } }
    /// The ASCII art's colours: the theme's three, or the cover's own.
    @Published var asciiColours: AsciiColouring { didSet { defaults.set(asciiColours.rawValue, forKey: Keys.asciiColours) } }
    /// The Vinyl look's parts linked to another of the theme's colours (`VinylPart`, `VinylInk`);
    /// a part not here uses its standard one.
    @Published var vinylLinks: [String: String] { didSet { defaults.set(vinylLinks, forKey: Keys.vinylLinks) } }
    /// The Music page tinted by the playing song's cover, blurred and faint; on by default.
    @Published var albumTint: Bool { didSet { defaults.set(albumTint, forKey: Keys.albumTint) } }
    /// The Music page's look (Settings → Appearance → Album art): the standard page, or Terminal.
    @Published var musicLook: MusicLook { didSet { defaults.set(musicLook.rawValue, forKey: Keys.musicLook) } }


    enum Keys {
        /// Who shows on Wisp's page (`WispCharacter`); unset is Wisp.
        static let wispCharacter = "wisp.character"
        /// KemoSabe's look (`KemoSabeLook`): a palette's id or "glass"; unset is Apricot.
        static let kemoSabeLook = "kemosabe.look"
        /// Whether KemoSabe tells a cloud model when you're free (`KemoSabeGateway`); unset is no.
        static let kemoSabeShareFreeTimes = "kemosabe.shareFreeTimes"
        static let clock24 = "widget.clock.24h"
        static let clockSeconds = "widget.clock.seconds"
        static let clockZone = "widget.clock.secondZone"
        static let unit = "widget.weather.unit"
        static let presets = "widget.timer.presets"
        static let worldCities = "widget.worldClock.cities"   // 2.68–2.69 World Clock, read once
        static let clockStyle = "widget.clock.style"
        static let clockPlaces = "widget.clock.places"
        static let clockPin = "widget.clock.pin"
        static let birthday = "calendar.life.birthday"
        static let lifespan = "calendar.life.lifespan"
        static let asciiCover = "music.ascii"
        static let asciiStyle = "music.ascii.style"
        static let asciiScene = "music.ascii.scene"
        static let asciiAround = "music.ascii.around"
        static let asciiDetail = "music.ascii.detail"
        static let asciiColours = "music.ascii.colours"
        static let vinylLinks = "music.vinyl.colours"
        static let albumTint = "music.tint"
        static let musicLook = "music.look"
        /// The Timers page's Focus and Notch chips, for the next timer started.
        static let timersNextFocus = "timers.nextFocus"
        static let timersNextHidden = "timers.nextHidden"
        /// The Weather page's chosen place, in the Clock's place format; unset is automatic.
        static let weatherPlace = "weather.place"
        static let closedNotchDrawer = "settings.drawer.closedNotch"
        static let themeDrawer = "settings.drawer.theme"
        /// After a timer's prefix (`timer`, `timer2`, `timer3`): what it does when done.
        static let timerWhenDoneSuffix = ".whenDone"
        static let timerTintSuffix = ".tint"
        static let timerTintChoiceSuffix = ".tintChoice"
        static let timerShowsInNotchSuffix = ".showsInNotch"
        static let timerFocusSuffix = ".focus"
        static let terminalTab = "terminal.tab"
        static let converterRevealResults = "converter.revealResults"
        static let clipboardPasteQueue = "clipboard.pasteQueue"
        /// What the user named each desktop, by its Space uuid.
        static let spaceNames = "spaces.names"
        /// Tape's switch; off unless turned on.
        static let tapeEnabled = "tape.enabled"
        /// Set on the first switch-on, once the separate app's settings have been looked at.
        static let tapeImported = "tape.imported"
        static let tapeGap = "tape.gap"
        static let tapeEdgeGap = "tape.edgeGap"
        static let tapeCentering = "tape.centering"
        static let tapeReduceMotion = "tape.reduceMotion"
        static let tapeSharedWidths = "tape.layout.sharedWidths"
        static let tapeAppPolicy = "tape.apps.policy"
        static let tapeAppPaths = "tape.apps.paths"
        static let tapeDisabledDisplays = "tape.displays.disabled"
        /// The desktops Tape stays off, by Space uuid; a new desktop is on.
        static let tapeDisabledSpaces = "tape.spaces.disabled"
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
            Keys.presets: [5, 15, 25]
        ])
        clockStyle = ClockStyle(rawValue: defaults.string(forKey: Keys.clockStyle) ?? "") ?? .regular
        clockPin = defaults.data(forKey: Keys.clockPin).flatMap { try? JSONDecoder().decode(ClockPin.self, from: $0) }
        temperatureUnit = .preferred()
        let presets = (defaults.array(forKey: Keys.presets) as? [Int] ?? []).filter { (1...600).contains($0) }
        timerPresets = presets.isEmpty ? [5, 15, 25] : Array(presets.prefix(3))
        birthday = (defaults.object(forKey: Keys.birthday) as? Double).map(Date.init(timeIntervalSince1970:))
        let span = defaults.integer(forKey: Keys.lifespan)
        lifespan = LifeProgress.lifespans.contains(span) ? span : LifeProgress.defaultLifespan
        asciiCover = defaults.bool(forKey: Keys.asciiCover)
        asciiStyle = AsciiStyle(rawValue: defaults.string(forKey: Keys.asciiStyle) ?? "") ?? .braille
        asciiScene = AsciiScene(rawValue: defaults.string(forKey: Keys.asciiScene) ?? "") ?? .vinyl
        asciiAround = AsciiAround(rawValue: defaults.string(forKey: Keys.asciiAround) ?? "") ?? .off
        // Horizon (a scene until 3.66, then an Around effect) is gone: its cover shows on its own.
        if defaults.string(forKey: Keys.asciiScene) == "horizon" { asciiScene = .cover }
        asciiDetail = AsciiDetail(rawValue: defaults.string(forKey: Keys.asciiDetail) ?? "") ?? .medium
        asciiColours = AsciiColouring(rawValue: defaults.string(forKey: Keys.asciiColours) ?? "") ?? .theme
        vinylLinks = defaults.dictionary(forKey: Keys.vinylLinks) as? [String: String] ?? [:]
        albumTint = defaults.object(forKey: Keys.albumTint) as? Bool ?? true
        musicLook = MusicLook(rawValue: defaults.string(forKey: Keys.musicLook) ?? "") ?? .standard
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
