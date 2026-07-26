import SwiftUI

/// Day / month / year progress bars — a gentle memento of passing time.
struct ProgressWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 7) {
                bar("Day", value: dayProgress(context.date), tint: .blue)
                bar("Month", value: monthProgress(context.date), tint: .purple)
                bar("Year", value: yearProgress(context.date), tint: .pink)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bar(_ label: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, proxy.size.width * value))
                }
            }
            .frame(height: 5)

            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    /// Measured against the calendar's own day length rather than a fixed
    /// 86,400s, so the bar still lands on 100% across a daylight-saving change.
    private func dayProgress(_ date: Date) -> Double {
        progress(of: .day, at: date)
    }

    private func monthProgress(_ date: Date) -> Double {
        progress(of: .month, at: date)
    }

    private func yearProgress(_ date: Date) -> Double {
        progress(of: .year, at: date)
    }

    private func progress(of component: Calendar.Component, at date: Date) -> Double {
        guard let interval = Calendar.current.dateInterval(of: component, for: date),
              interval.duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(interval.start) / interval.duration, 0), 1)
    }
}
