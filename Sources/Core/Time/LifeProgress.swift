import Foundation

/// Your life in weeks, for the Calendar page's Life view: a row of 52 weeks per year
/// from your birthday to the age you choose to count to, how much of it has passed,
/// and what's left (weeks, weekends, birthdays, days).
struct LifeProgress: Equatable {
    static let weeksPerYear = 52
    static let lifespans = 60...110
    static let defaultLifespan = 80

    let birthday: Date
    let lifespan: Int
    let now: Date
    let calendar: Calendar

    init(birthday: Date, lifespan: Int = LifeProgress.defaultLifespan, now: Date = Date(), calendar: Calendar = .current) {
        self.birthday = birthday
        self.lifespan = min(max(lifespan, Self.lifespans.lowerBound), Self.lifespans.upperBound)
        self.now = now
        self.calendar = calendar
    }

    /// The day you reach `lifespan`.
    var end: Date { calendar.date(byAdding: .year, value: lifespan, to: birthday) ?? birthday }

    /// Whole years old.
    var age: Int { max(0, calendar.dateComponents([.year], from: birthday, to: now).year ?? 0) }

    /// Each year of life is a row of 52 weeks, from that birthday: years and weeks so far.
    var lived: (years: Int, weeks: Int) {
        guard now > birthday else { return (0, 0) }
        let years = min(age, lifespan)
        guard years < lifespan, let lastBirthday = calendar.date(byAdding: .year, value: years, to: birthday) else { return (lifespan, 0) }
        let days = calendar.dateComponents([.day], from: lastBirthday, to: now).day ?? 0
        return (years, min(Self.weeksPerYear - 1, days / 7))
    }

    var totalWeeks: Int { lifespan * Self.weeksPerYear }

    /// Weeks before this one (this week is `weeksLived`, counting from 0).
    var weeksLived: Int { min(totalWeeks, lived.years * Self.weeksPerYear + lived.weeks) }

    var weeksLeft: Int { max(0, totalWeeks - weeksLived - 1) }

    /// How much of the span has passed, 0…1, by days.
    var fraction: Double {
        let total = end.timeIntervalSince(birthday)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(birthday) / total))
    }

    var daysLeft: Int { max(0, calendar.dateComponents([.day], from: now, to: end).day ?? 0) }

    /// Saturdays still to come before the end.
    var weekendsLeft: Int {
        guard now < end else { return 0 }
        let weekday = calendar.component(.weekday, from: now)
        let untilSaturday = (7 - weekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: untilSaturday, to: calendar.startOfDay(for: now)), first < end else { return 0 }
        let days = calendar.dateComponents([.day], from: first, to: end).day ?? 0
        return days / 7 + 1
    }

    /// Birthdays still to come, up to and including the last one counted.
    var birthdaysLeft: Int { max(0, lifespan - age) }

    /// Days until the next birthday (0 on the day).
    var daysToNextBirthday: Int {
        let start = calendar.startOfDay(for: now)
        let parts = calendar.dateComponents([.month, .day], from: birthday)
        guard let next = calendar.nextDate(after: start.addingTimeInterval(-1), matching: parts, matchingPolicy: .nextTimePreservingSmallerComponents)
        else { return 0 }
        return max(0, calendar.dateComponents([.day], from: start, to: next).day ?? 0)
    }
}
