import Foundation

/// Geography for the Clock's Map style: a coarse land grid, where each time zone is,
/// the nearest time zone to any point, and where it's day.
enum ClockGeography {
    /// Land ("#") on an equirectangular grid of 3.75° cells, 96 across from 180°W,
    /// from 82.5°N down to 56.25°S (Antarctica left out).
    static let land: [String] = [
        ".......................####################..............................#......................",
        "................###.#######..##############.........#.....................####..................",
        "...............#####.#######.....##########...................##......############...##.........",
        "....#################.########....########..........######....##################################",
        "##..######################..###...#####...##.......#############################################",
        "....####################...####....##............##############################################.",
        ".....##....############....#####..................###.################################....##....",
        "............##############.######.............##..###################################....##.....",
        "..............###################..............#######################################..........",
        "...............################..#.............######################################...........",
        "...............###############................##########...#########################..#.........",
        "...............#############..................##....###############################..#..........",
        "................############..................#####.....########################..#.##..........",
        ".................##########..................#######.##..########################...............",
        ".................######...#..................####################################...............",
        "...................###......................####################..##############................",
        "....................##..#..#...............###############.#####...###########..................",
        ".....................####...................###################....###...####...#...............",
        "........................##.................##################.......##....###...................",
        ".........................#..####............##################......#.......#....#..............",
        "...........................#######...........################..................#................",
        "...........................########...............##########..............##.###................",
        "..........................##########..............#########................#.##.#..##...........",
        "..........................#############............########.................#.......###.........",
        "...........................############............########..........................#.#........",
        "...........................###########.............########........................#............",
        "............................##########.............########.#....................######.........",
        ".............................########..............#######..#..................#########........",
        ".............................#######................######..#.................###########.......",
        ".............................######.................#####.....................###########.......",
        ".............................#####...................###.......................##########.......",
        ".............................####..............................................#.....###........",
        "............................####......................................................#.......#.",
        "............................###..............................................................#..",
        "............................##..................................................................",
        "............................##..................................................................",
        "............................##.................................................................."
    ]
    static let columns = 96
    static let northEdge = 82.5
    static let cell = 3.75
    static var rows: Int { land.count }
    static var southEdge: Double { northEdge - Double(rows) * cell }

    /// Each row's land cells, decoded once.
    private static let landCells: [[Bool]] = land.map { $0.map { $0 == "#" } }

    static func isLand(row: Int, column: Int) -> Bool {
        guard landCells.indices.contains(row), landCells[row].indices.contains(column) else { return false }
        return landCells[row][column]
    }

    struct Zone: Equatable {
        let identifier: String
        let countryCode: String
        let latitude: Double
        let longitude: Double
        /// "Los Angeles" from "America/Los_Angeles".
        var name: String { ClockGeography.cityName(identifier) }
        /// "United States", in the user's language.
        var country: String { Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode }
    }

    /// "Los Angeles" from "America/Los_Angeles", "Ho Chi Minh" from "Asia/Ho_Chi_Minh".
    static func cityName(_ identifier: String) -> String {
        identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
    }

    /// The country a zone belongs to, when zone.tab lists it.
    static func country(of identifier: String) -> String? {
        zones.first { $0.identifier == identifier }?.country
    }

    /// Zones whose city or country matches a search, best matches first.
    static func search(_ text: String) -> [Zone] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        func matches(_ value: String) -> Bool { value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        func starts(_ value: String) -> Bool { value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }
        return zones.filter { matches($0.name) || matches($0.country) }
            .sorted { (starts($0.name) ? 0 : 1, $0.name) < (starts($1.name) ? 0 : 1, $1.name) }
    }

    /// Every zone with its principal city's position, from the system's zone.tab.
    static let zones: [Zone] = {
        guard let text = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: "\t")
            guard fields.count >= 3, let position = coordinates(String(fields[1])) else { return nil }
            return Zone(identifier: String(fields[2]), countryCode: String(fields[0]),
                        latitude: position.latitude, longitude: position.longitude)
        }
    }()

    /// Parses ISO 6709 "+DDMM+DDDMM" or "+DDMMSS+DDDMMSS".
    static func coordinates(_ text: String) -> (latitude: Double, longitude: Double)? {
        let characters = Array(text)
        guard let split = characters.indices.dropFirst().first(where: { characters[$0] == "+" || characters[$0] == "-" }) else { return nil }
        func degrees(_ part: ArraySlice<Character>, degreeDigits: Int) -> Double? {
            guard let sign = part.first, sign == "+" || sign == "-" else { return nil }
            let digits = String(part.dropFirst())
            guard digits.count >= degreeDigits + 2, let value = Int(digits) else { return nil }
            let withSeconds = digits.count >= degreeDigits + 4
            let (d, m, s) = withSeconds ? (value / 10000, value / 100 % 100, value % 100) : (value / 100, value % 100, 0)
            let result = Double(d) + Double(m) / 60 + Double(s) / 3600
            return sign == "-" ? -result : result
        }
        guard let latitude = degrees(characters[..<split], degreeDigits: 2),
              let longitude = degrees(characters[split...], degreeDigits: 3) else { return nil }
        return (latitude, longitude)
    }

    /// Where a place (a zone identifier or "local") is on the map.
    static func position(of place: String) -> (latitude: Double, longitude: Double)? {
        if let saved = WidgetOptions.savedPosition(place) { return saved }
        let identifier = place == WidgetOptions.local ? TimeZone.current.identifier : WidgetOptions.zoneIdentifier(place)
        return zones.first { $0.identifier == identifier }.map { ($0.latitude, $0.longitude) }
    }

    /// The zone whose city is closest to a point, by great-circle distance.
    static func nearestZone(latitude: Double, longitude: Double) -> Zone? {
        func distance(_ zone: Zone) -> Double {
            let (p1, p2) = (latitude * .pi / 180, zone.latitude * .pi / 180)
            let dl = (zone.longitude - longitude) * .pi / 180
            return acos(min(1, max(-1, sin(p1) * sin(p2) + cos(p1) * cos(p2) * cos(dl))))
        }
        return zones.min { distance($0) < distance($1) }
    }

    /// Whether the sun is up at a point, from the sun's approximate position.
    static func isDaylight(latitude: Double, longitude: Double, sun: (latitude: Double, longitude: Double)) -> Bool {
        let (p, d) = (latitude * .pi / 180, sun.latitude * .pi / 180)
        let h = (longitude - sun.longitude) * .pi / 180
        return sin(p) * sin(d) + cos(p) * cos(d) * cos(h) > 0
    }

    /// Where the sun is overhead: declination from the day of the year, longitude from UTC time.
    static func subsolarPoint(_ date: Date) -> (latitude: Double, longitude: Double) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let day = Double(utc.ordinality(of: .day, in: .year, for: date) ?? 1)
        let parts = utc.dateComponents([.hour, .minute, .second], from: date)
        let hours = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
        let declination = 23.44 * sin(2 * .pi * (284 + day) / 365)
        return (declination, (12 - hours) * 15)
    }
}
