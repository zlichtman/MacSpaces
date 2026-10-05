import SwiftUI
import AppKit

/// How far through the calendar year a moment is. Day-based figures match
/// how people count ("day 271 of 365"); the fraction is continuous so the bar
/// moves through the day.
struct YearProgress: Equatable {
    let year: Int
    let dayOfYear: Int
    let totalDays: Int
    let fraction: Double

    var percent: Int { Int((fraction * 100).rounded(.down)) }
    var daysRemaining: Int { totalDays - dayOfYear }

    init(date: Date = Date(), calendar: Calendar = .current) {
        year = calendar.component(.year, from: date)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? date
        let next = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? date
        totalDays = calendar.dateComponents([.day], from: start, to: next).day ?? 365
        dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let length = next.timeIntervalSince(start)
        fraction = length > 0 ? min(max(date.timeIntervalSince(start) / length, 0), 1) : 0
    }
}

/// A thin bar with quarter ticks, filled to today's point in the year.
struct YearProgressBar: View {
    let progress: YearProgress
    var height: CGFloat = 5
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(theme.notch.accent)
                    .frame(width: max(height, proxy.size.width * progress.fraction))
                ForEach([0.25, 0.5, 0.75], id: \.self) { quarter in
                    Rectangle().fill(Color.primary.opacity(0.25))
                        .frame(width: 1, height: height + 3)
                        .offset(x: proxy.size.width * quarter)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Year progress")
        .accessibilityValue("\(progress.percent) percent of \(progress.year), \(progress.daysRemaining) days left")
    }
}

/// "2026 · Day 271 of 365 · 74% · 94 days left" above the year bar.
struct YearProgressHeader: View {
    let progress: YearProgress
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(progress.year)).font(.system(size: compact ? 10 : 12, weight: .bold))
                Text("\(progress.percent)% through the year")
                    .font(.system(size: compact ? 9 : 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(progress.daysRemaining) days left")
                    .font(.system(size: compact ? 9 : 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            YearProgressBar(progress: progress, height: compact ? 3 : 5)
        }
    }
}

/// A month of days with today in the accent colour and up to three dots
/// per day in the colours of that day's calendars.
struct MonthGrid: View {
    @Binding var month: Date
    @Binding var selected: Date
    let events: [CalendarEventItem]
    var cellHeight: CGFloat = 30
    var showsNavigation = true
    @ObservedObject private var theme = ThemeStore.shared

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 2) {
            if showsNavigation { header }
            HStack(spacing: 0) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.system(size: cellHeight < 24 ? 8 : 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            ForEach(weeks, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in cell(day) }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(month, format: .dateTime.month(.wide).year())
                .font(.system(size: 14, weight: .bold))
            Spacer()
            if !calendar.isDate(month, equalTo: Date(), toGranularity: .month) {
                Button("Today") {
                    withAnimation(.easeInOut(duration: 0.2)) { month = Date(); selected = Date() }
                }
                .buttonStyle(WidgetChipStyle(height: 22))
            }
            navButton("chevron.left", "Previous month", -1)
            navButton("chevron.right", "Next month", 1)
        }
        .padding(.bottom, 4)
    }

    private func navButton(_ symbol: String, _ label: String, _ offset: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                month = calendar.date(byAdding: .month, value: offset, to: month) ?? month
            }
        } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
    }

    private func cell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let colors = dotColors(on: day)
        let compact = cellHeight < 24
        return Button { selected = day } label: {
            VStack(spacing: compact ? 1 : 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: compact ? 9 : 12, weight: isToday ? .bold : .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? AnyShapeStyle(Color.black.opacity(0.85))
                                     : inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: compact ? 16 : 24, height: compact ? 14 : 20)
                    .background {
                        if isToday {
                            Circle().fill(theme.notch.accent)
                        } else if isSelected {
                            Circle().fill(Color.primary.opacity(0.14))
                        }
                    }
                HStack(spacing: 2) {
                    ForEach(colors.indices, id: \.self) { index in
                        Circle().fill(colors[index].opacity(inMonth ? 1 : 0.4))
                            .frame(width: compact ? 2.5 : 4, height: compact ? 2.5 : 4)
                    }
                }
                .frame(height: compact ? 3 : 4)
            }
            .frame(maxWidth: .infinity, minHeight: cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted)
                            + (colors.isEmpty ? "" : ", \(events(on: day).count) events"))
    }

    private func events(on day: Date) -> [CalendarEventItem] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.startDate < end && $0.endDate > start }
    }

    private func dotColors(on day: Date) -> [Color] {
        var seen = Set<String>()
        return events(on: day).compactMap { event -> Color? in
            let key = event.color.map { "\($0.red)-\($0.green)-\($0.blue)" } ?? "default"
            guard seen.insert(key).inserted else { return nil }
            return event.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? theme.notch.accent
        }
        .prefix(3).map { $0 }
    }

    /// Very short weekday names starting from the locale's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Whole weeks covering the displayed month.
    private var weeks: [[Date]] {
        guard let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let days = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count else { return [] }
        let leading = (calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday + 7) % 7
        let total = Int((Double(leading + days) / 7).rounded(.up)) * 7
        let dates = (0..<total).compactMap { calendar.date(byAdding: .day, value: $0 - leading, to: firstOfMonth) }
        return stride(from: 0, to: dates.count, by: 7).map { Array(dates[$0..<min($0 + 7, dates.count)]) }
    }
}
