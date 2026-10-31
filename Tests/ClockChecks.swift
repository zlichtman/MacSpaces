import CoreGraphics
import Foundation

@main struct ClockChecks {
    static func main() {
        globe()
        matchUp()
        life()
        print("Clock checks passed: globe projection there and back, far side hidden, dragging and tilt limits, shortest spins; Match up windows across time zones, waking-hours fallback, best window; life in weeks, what's left and the next birthday")
    }

    static func globe() {
        let view = GlobeProjection(latitude: 20, longitude: -87.6, center: CGPoint(x: 150, y: 150), radius: 140)
        // The centre of the view is the middle of the disc, facing you.
        let middle = view.project(latitude: 20, longitude: -87.6)!
        precondition(abs(middle.point.x - 150) < 0.001 && abs(middle.point.y - 150) < 0.001 && abs(middle.facing - 1) < 1e-9)
        // North is up, east is right.
        precondition(view.project(latitude: 40, longitude: -87.6)!.point.y < 150 && view.project(latitude: 20, longitude: -70)!.point.x > 150)
        precondition(view.project(latitude: -20, longitude: 92.4) == nil, "The far side isn't drawn")
        // A click finds the place it shows.
        for (lat, lon) in [(41.88, -87.63), (51.5, -0.12), (-23.5, -46.6), (19.4, -99.1)] {
            guard let shown = view.project(latitude: lat, longitude: lon) else { preconditionFailure("\(lat),\(lon) should face the viewer") }
            let back = view.coordinate(at: shown.point)!
            precondition(abs(back.latitude - lat) < 1e-6 && abs(GlobeProjection.wrapped(back.longitude - lon)) < 1e-6, "Round trip \(lat),\(lon)")
        }
        precondition(view.coordinate(at: CGPoint(x: 150 + 141, y: 150)) == nil, "Off the disc is no place")
        // Dragging right turns the globe so places further west come into view; up and down tip it, within limits.
        precondition(view.dragged(by: CGSize(width: 100, height: 0)).longitude < view.longitude)
        precondition(view.dragged(by: CGSize(width: 0, height: 10_000)).latitude == GlobeProjection.tilt.upperBound)
        precondition(view.dragged(by: CGSize(width: 0, height: -10_000)).latitude == GlobeProjection.tilt.lowerBound)
        // Spinning to a place takes the short way round.
        precondition(GlobeProjection.nearestLongitude(-170, from: 170) == 190, "Across the date line, not back round")
        precondition(GlobeProjection.nearestLongitude(10, from: 350) == 370)
        precondition(GlobeProjection.wrapped(190) == -170 && GlobeProjection.wrapped(-190) == 170 && GlobeProjection.wrapped(180) == -180)
    }

    static func matchUp() {
        let chicago = TimeZone(identifier: "America/Chicago")!, london = TimeZone(identifier: "Europe/London")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!, berlin = TimeZone(identifier: "Europe/Berlin")!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = chicago
        // 15 January: Chicago UTC−6, London UTC+0, Berlin UTC+1, Tokyo UTC+9.
        let day = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 12))!
        func local(_ date: Date) -> Double { TimeOverlap.hour(of: date, in: chicago) }
        // Chicago and London: 9–12 in Chicago is 3–6 pm in London.
        let pair = TimeOverlap.matchUp([chicago, london], on: day, here: chicago)
        precondition(!pair.relaxed && pair.windows.count == 1 && local(pair.windows[0].start) == 9 && local(pair.windows[0].end) == 12,
                     "Chicago and London overlap 9 am to noon in Chicago")
        // London and Berlin: 9–5 London (an hour less at each end of Berlin's day).
        let europe = TimeOverlap.matchUp([london, berlin], on: day, here: london)
        precondition(europe.best.map { TimeOverlap.hour(of: $0.start, in: london) } == 9 && europe.best!.duration == 8 * 3600)
        // Chicago and Tokyo never share working hours, so waking hours are offered.
        let far = TimeOverlap.matchUp([chicago, tokyo], on: day, here: chicago)
        precondition(far.relaxed && !far.windows.isEmpty, "No working overlap falls back to waking hours")
        for window in far.windows {
            precondition(TimeOverlap.isWithin(TimeOverlap.wakingHours, at: window.start, in: tokyo)
                         && TimeOverlap.isWithin(TimeOverlap.wakingHours, at: window.start, in: chicago))
        }
        // One place: its own working day. None: nothing.
        let one = TimeOverlap.matchUp([chicago], on: day, here: chicago)
        precondition(one.best.map { local($0.start) } == 9 && one.best!.duration == 9 * 3600)
        precondition(TimeOverlap.matchUp([], on: day, here: chicago).windows.isEmpty)
        // The strip is today here from midnight in half hours.
        let slots = TimeOverlap.slots(on: day, here: chicago)
        precondition(slots.count == 48 && local(slots[0]) == 0 && local(slots[47]) == 23.5)
    }

    static func life() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        let birthday = day(1990, 6, 15)
        // 35 and three weeks: row 35, week 3.
        let life = LifeProgress(birthday: birthday, lifespan: 80, now: day(2025, 7, 7), calendar: calendar)
        precondition(life.age == 35 && life.lived.years == 35 && life.lived.weeks == 3, "Row 35, week 3")
        precondition(life.totalWeeks == 4160 && life.weeksLived == 35 * 52 + 3 && life.weeksLeft == 4160 - life.weeksLived - 1)
        precondition(abs(life.fraction - 35.06 / 80) < 0.002, "About 43.8% of 80 years")
        precondition(life.birthdaysLeft == 45)
        precondition(life.daysToNextBirthday == 343, "15 June 2026 is 343 days after 7 July 2025")
        precondition(LifeProgress(birthday: birthday, now: day(2025, 6, 15), calendar: calendar).daysToNextBirthday == 0, "Today is the birthday")
        // Weekends: 7 July 2025 is a Monday, so the first is the 12th; one per week to the end.
        let weekends = life.weekendsLeft
        precondition(abs(weekends - life.daysLeft / 7) <= 1, "About one weekend a week")
        // Before birth, past the end, and out-of-range spans.
        let unborn = LifeProgress(birthday: day(2030, 1, 1), now: day(2025, 1, 1), calendar: calendar)
        precondition(unborn.weeksLived == 0 && unborn.fraction == 0 && unborn.age == 0)
        let past = LifeProgress(birthday: day(1900, 1, 1), lifespan: 80, now: day(2025, 1, 1), calendar: calendar)
        precondition(past.fraction == 1 && past.weeksLeft == 0 && past.daysLeft == 0 && past.weekendsLeft == 0 && past.weeksLived == past.totalWeeks)
        precondition(LifeProgress(birthday: birthday, lifespan: 200, calendar: calendar).lifespan == 110 && LifeProgress(birthday: birthday, lifespan: 10, calendar: calendar).lifespan == 60)
    }
}
