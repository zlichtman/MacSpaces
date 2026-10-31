import Foundation

/// Match up: when chosen places are all within working hours, across today here, in
/// half-hour steps. If no time works for everyone, waking hours are tried instead.
enum TimeOverlap {
    /// 9 am to 6 pm in each place.
    static let workingHours = 9.0..<18.0
    /// 8 am to 10 pm, when working hours never line up.
    static let wakingHours = 8.0..<22.0
    static let step: TimeInterval = 30 * 60
    static let steps = 48

    struct Window: Equatable {
        let start: Date
        let end: Date
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    struct Result: Equatable {
        /// Times that work for everyone, earliest first.
        let windows: [Window]
        /// No working-hours overlap, so these are waking hours.
        let relaxed: Bool
        /// The longest window (the earliest of equals).
        var best: Window? { windows.max { $0.duration < $1.duration || ($0.duration == $1.duration && $0.start > $1.start) } }
    }

    /// Today here from midnight, as the half-hour starts the strips are drawn in.
    static func slots(on day: Date, here: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = here
        let midnight = calendar.startOfDay(for: day)
        return (0..<steps).map { midnight.addingTimeInterval(Double($0) * step) }
    }

    /// The hour of the day (with fractions) a moment is in a place.
    static func hour(of date: Date, in zone: TimeZone) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }

    static func isWithin(_ hours: Range<Double>, at date: Date, in zone: TimeZone) -> Bool {
        // The whole half hour must fit, so 5:30 pm still counts for a 6 pm close.
        hours.contains(hour(of: date, in: zone)) && hour(of: date.addingTimeInterval(step - 60), in: zone) < hours.upperBound
    }

    static func matchUp(_ zones: [TimeZone], on day: Date, here: TimeZone = .current) -> Result {
        let slots = slots(on: day, here: here)
        func windows(_ hours: Range<Double>) -> [Window] {
            var found: [Window] = []
            var start: Date?
            for slot in slots {
                let works = !zones.isEmpty && zones.allSatisfy { isWithin(hours, at: slot, in: $0) }
                if works, start == nil { start = slot }
                if !works, let open = start { found.append(Window(start: open, end: slot)); start = nil }
            }
            if let open = start, let last = slots.last { found.append(Window(start: open, end: last.addingTimeInterval(step))) }
            return found
        }
        let working = windows(workingHours)
        return working.isEmpty ? Result(windows: windows(wakingHours), relaxed: true) : Result(windows: working, relaxed: false)
    }
}
